import { describe, expect, it } from 'vitest'
import {
  DISPUTE_TRANSITIONS,
  applyDisputeEvent,
  canTransitionDispute,
  recordAcceptance,
} from './dispute-machine.js'
import { unwrap } from './result.js'
import {
  DISPUTE_EVENTS,
  DISPUTE_STATES,
  TERMINAL_DISPUTE_STATES,
  isTerminalDisputeState,
  type Actor,
  type DisputeEvent,
  type DisputeState,
  type Role,
} from './types.js'

const ACTORS: readonly Actor[] = ['buyer', 'seller', 'system']

describe('dispute table integrity', () => {
  it('has no duplicate (from, event) pairs', () => {
    const seen = new Set<string>()
    for (const rule of DISPUTE_TRANSITIONS) {
      const key = `${rule.from}::${rule.event}`
      expect(seen.has(key), `duplicate rule for ${key}`).toBe(false)
      seen.add(key)
    }
  })

  it('never lets a terminal state transition out', () => {
    for (const terminal of TERMINAL_DISPUTE_STATES) {
      expect(DISPUTE_TRANSITIONS.filter((r) => r.from === terminal)).toHaveLength(0)
    }
  })

  it('makes every declared state reachable from open', () => {
    const reached = new Set<DisputeState>(['open'])
    const queue: DisputeState[] = ['open']
    while (queue.length > 0) {
      const current = queue.shift()
      if (current === undefined) break
      for (const rule of DISPUTE_TRANSITIONS.filter((r) => r.from === current)) {
        if (!reached.has(rule.to)) {
          reached.add(rule.to)
          queue.push(rule.to)
        }
      }
    }
    for (const state of DISPUTE_STATES) {
      expect(reached.has(state), `${state} is unreachable from open`).toBe(true)
    }
  })
})

describe('applyDisputeEvent, exhaustively', () => {
  it('agrees with the table for every state, event and actor combination', () => {
    for (const state of DISPUTE_STATES) {
      for (const event of DISPUTE_EVENTS) {
        for (const actor of ACTORS) {
          const result = applyDisputeEvent(state, event, actor)
          const rule = DISPUTE_TRANSITIONS.find((r) => r.from === state && r.event === event)

          if (isTerminalDisputeState(state)) {
            expect(result.ok, `${state}/${event}/${actor}`).toBe(false)
            continue
          }
          if (rule === undefined || !rule.actors.includes(actor)) {
            expect(result.ok, `${state}/${event}/${actor}`).toBe(false)
            continue
          }
          expect(result.ok, `${state}/${event}/${actor}`).toBe(true)
          if (result.ok) expect(result.value).toBe(rule.to)
        }
      }
    }
  })

  it('keeps canTransitionDispute consistent with applyDisputeEvent', () => {
    for (const state of DISPUTE_STATES) {
      for (const event of DISPUTE_EVENTS) {
        for (const actor of ACTORS) {
          const viaApply = applyDisputeEvent(state, event, actor).ok
          const viaCan = canTransitionDispute(state, event, actor) && !isTerminalDisputeState(state)
          expect(viaCan, `${state}/${event}/${actor}`).toBe(viaApply)
        }
      }
    }
  })
})

describe('the AI proposes, it does not rule', () => {
  it('never lets a party close a dispute by accepting alone', () => {
    // accept_proposal is system-only on purpose: the system fires it after it
    // has seen both acceptances, never on one party's request.
    expect(applyDisputeEvent('proposal_issued', 'accept_proposal', 'buyer').ok).toBe(false)
    expect(applyDisputeEvent('proposal_issued', 'accept_proposal', 'seller').ok).toBe(false)
    expect(applyDisputeEvent('proposal_issued', 'accept_proposal', 'system').ok).toBe(true)
  })

  it('lets a single refusal escalate to a human', () => {
    expect(unwrap(applyDisputeEvent('proposal_issued', 'reject_proposal', 'buyer'))).toBe('escalated')
    expect(unwrap(applyDisputeEvent('proposal_issued', 'reject_proposal', 'seller'))).toBe('escalated')
  })

  it('can skip the proposal entirely when the model is not trusted for the case', () => {
    expect(unwrap(applyDisputeEvent('ai_review', 'escalate', 'system'))).toBe('escalated')
  })

  it('walks the fast path when both sides agree', () => {
    let state: DisputeState = 'open'
    state = unwrap(applyDisputeEvent(state, 'submit_for_ai', 'system'))
    expect(state).toBe('ai_review')
    state = unwrap(applyDisputeEvent(state, 'issue_proposal', 'system'))
    expect(state).toBe('proposal_issued')
    state = unwrap(applyDisputeEvent(state, 'accept_proposal', 'system'))
    expect(state).toBe('accepted')
  })

  it('walks the escalation path to a human decision', () => {
    let state: DisputeState = 'open'
    state = unwrap(applyDisputeEvent(state, 'submit_for_ai', 'system'))
    state = unwrap(applyDisputeEvent(state, 'issue_proposal', 'system'))
    state = unwrap(applyDisputeEvent(state, 'reject_proposal', 'seller'))
    state = unwrap(applyDisputeEvent(state, 'assign_reviewer', 'system'))
    state = unwrap(applyDisputeEvent(state, 'issue_human_resolution', 'system'))
    expect(state).toBe('resolved_by_human')
  })
})

describe('recordAcceptance', () => {
  it('requires both sides before a dispute may close', () => {
    const first = recordAcceptance([], 'buyer')
    expect(first.acceptedBy).toEqual(['buyer'])
    expect(first.bothAccepted).toBe(false)

    const second = recordAcceptance(first.acceptedBy, 'seller')
    expect(second.bothAccepted).toBe(true)
  })

  it('is idempotent, so a retried request cannot close a dispute alone', () => {
    let outcome = recordAcceptance([], 'buyer')
    for (let i = 0; i < 5; i++) {
      outcome = recordAcceptance(outcome.acceptedBy, 'buyer')
    }
    expect(outcome.acceptedBy).toEqual(['buyer'])
    expect(outcome.bothAccepted).toBe(false)
  })

  it('does not care which side accepts first', () => {
    const roles: Role[] = ['seller', 'buyer']
    let acceptedBy: readonly Role[] = []
    for (const role of roles) {
      acceptedBy = recordAcceptance(acceptedBy, role).acceptedBy
    }
    expect(recordAcceptance(acceptedBy, 'buyer').bothAccepted).toBe(true)
  })

  it('does not mutate the array it was given', () => {
    const original: readonly Role[] = ['buyer']
    recordAcceptance(original, 'seller')
    expect(original).toEqual(['buyer'])
  })
})

describe('withdrawal', () => {
  it('lets a party drop a dispute they opened, before it reaches the model', () => {
    expect(unwrap(applyDisputeEvent('open', 'withdraw_dispute', 'buyer'))).toBe('withdrawn')
  })

  it('does not allow withdrawal once the case is with the model or a reviewer', () => {
    const closedToWithdrawal: DisputeState[] = ['ai_review', 'proposal_issued', 'escalated', 'human_review']
    for (const state of closedToWithdrawal) {
      for (const actor of ACTORS) {
        const event: DisputeEvent = 'withdraw_dispute'
        expect(applyDisputeEvent(state, event, actor).ok, `${state}/${actor}`).toBe(false)
      }
    }
  })
})
