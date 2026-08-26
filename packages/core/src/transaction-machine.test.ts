import { describe, expect, it } from 'vitest'
import {
  identityGate,
  TRANSITIONS,
  applyEvent,
  availableEvents,
  availableEventsFor,
  canTransition,
  toMermaid,
} from './transaction-machine.js'
import { unwrap } from './result.js'
import {
  TERMINAL_TRANSACTION_STATES,
  TRANSACTION_EVENTS,
  TRANSACTION_STATES,
  isTerminalTransactionState,
  type Actor,
  type TransactionEvent,
  type TransactionState,
} from './types.js'

const ACTORS: readonly Actor[] = ['buyer', 'seller', 'system']

describe('transition table integrity', () => {
  it('has no duplicate (from, event) pairs', () => {
    const seen = new Set<string>()
    for (const rule of TRANSITIONS) {
      const key = `${rule.from}::${rule.event}`
      expect(seen.has(key), `duplicate rule for ${key}`).toBe(false)
      seen.add(key)
    }
  })

  it('only references declared states and events', () => {
    for (const rule of TRANSITIONS) {
      expect(TRANSACTION_STATES).toContain(rule.from)
      expect(TRANSACTION_STATES).toContain(rule.to)
      expect(TRANSACTION_EVENTS).toContain(rule.event)
    }
  })

  it('declares at least one actor per rule, and no empty actor lists', () => {
    for (const rule of TRANSITIONS) {
      expect(rule.actors.length, `${rule.from}::${rule.event} has no actors`).toBeGreaterThan(0)
    }
  })

  it('gives every rule a plain-language description', () => {
    for (const rule of TRANSITIONS) {
      expect(rule.describe.trim().length, `${rule.from}::${rule.event} is undocumented`).toBeGreaterThan(0)
    }
  })

  it('never lets a terminal state transition out', () => {
    for (const terminal of TERMINAL_TRANSACTION_STATES) {
      const outgoing = TRANSITIONS.filter((r) => r.from === terminal)
      expect(outgoing, `${terminal} should be terminal but has outgoing rules`).toHaveLength(0)
    }
  })

  it('leaves no non-terminal state without a way out', () => {
    for (const state of TRANSACTION_STATES) {
      if (isTerminalTransactionState(state)) continue
      expect(availableEvents(state).length, `${state} is a dead end`).toBeGreaterThan(0)
    }
  })

  it('makes every declared state reachable from draft', () => {
    const reached = new Set<TransactionState>(['draft'])
    const queue: TransactionState[] = ['draft']
    while (queue.length > 0) {
      const current = queue.shift()
      if (current === undefined) break
      for (const rule of TRANSITIONS.filter((r) => r.from === current)) {
        if (!reached.has(rule.to)) {
          reached.add(rule.to)
          queue.push(rule.to)
        }
      }
    }
    for (const state of TRANSACTION_STATES) {
      expect(reached.has(state), `${state} is unreachable from draft`).toBe(true)
    }
  })
})

describe('applyEvent, exhaustively', () => {
  it('agrees with the table for every state, event and actor combination', () => {
    let allowed = 0
    let refused = 0

    for (const state of TRANSACTION_STATES) {
      for (const event of TRANSACTION_EVENTS) {
        for (const actor of ACTORS) {
          const result = applyEvent(state, event, actor)
          const rule = TRANSITIONS.find((r) => r.from === state && r.event === event)

          if (isTerminalTransactionState(state)) {
            expect(result.ok, `${state}/${event}/${actor} should be refused`).toBe(false)
            if (!result.ok) expect(result.error.code).toBe('TERMINAL_STATE')
            refused++
            continue
          }

          if (rule === undefined) {
            expect(result.ok, `${state}/${event}/${actor} should be invalid`).toBe(false)
            if (!result.ok) expect(result.error.code).toBe('INVALID_TRANSITION')
            refused++
            continue
          }

          if (!rule.actors.includes(actor)) {
            expect(result.ok, `${state}/${event}/${actor} should be forbidden`).toBe(false)
            if (!result.ok) expect(result.error.code).toBe('ACTOR_NOT_PERMITTED')
            refused++
            continue
          }

          expect(result.ok, `${state}/${event}/${actor} should be allowed`).toBe(true)
          if (result.ok) expect(result.value).toBe(rule.to)
          allowed++
        }
      }
    }

    // Sanity check that the sweep actually exercised both outcomes.
    expect(allowed).toBeGreaterThan(0)
    expect(refused).toBeGreaterThan(0)
    expect(allowed + refused).toBe(
      TRANSACTION_STATES.length * TRANSACTION_EVENTS.length * ACTORS.length,
    )
  })

  it('keeps canTransition consistent with applyEvent', () => {
    for (const state of TRANSACTION_STATES) {
      for (const event of TRANSACTION_EVENTS) {
        for (const actor of ACTORS) {
          const viaApply = applyEvent(state, event, actor).ok
          const viaCan = canTransition(state, event, actor) && !isTerminalTransactionState(state)
          expect(viaCan, `${state}/${event}/${actor}`).toBe(viaApply)
        }
      }
    }
  })
})

describe('actor authorization', () => {
  it('lets only the seller declare delivery', () => {
    expect(applyEvent('active', 'mark_delivered', 'seller').ok).toBe(true)
    expect(applyEvent('active', 'mark_delivered', 'buyer').ok).toBe(false)
    expect(applyEvent('active', 'mark_delivered', 'system').ok).toBe(false)
  })

  it('lets only the buyer confirm or send back a delivery', () => {
    expect(applyEvent('delivered', 'confirm_delivery', 'buyer').ok).toBe(true)
    expect(applyEvent('delivered', 'confirm_delivery', 'seller').ok).toBe(false)
    expect(applyEvent('delivered', 'request_revision', 'buyer').ok).toBe(true)
    expect(applyEvent('delivered', 'request_revision', 'seller').ok).toBe(false)
  })

  it('reserves expiry, resolution and mutual cancellation for the system', () => {
    const systemOnly: [TransactionState, TransactionEvent][] = [
      ['pending_acceptance', 'expire'],
      ['disputed', 'resolve_dispute'],
      ['active', 'cancel_by_agreement'],
    ]
    for (const [state, event] of systemOnly) {
      expect(applyEvent(state, event, 'system').ok, `${state}/${event}`).toBe(true)
      expect(applyEvent(state, event, 'buyer').ok, `${state}/${event} by buyer`).toBe(false)
      expect(applyEvent(state, event, 'seller').ok, `${state}/${event} by seller`).toBe(false)
    }
  })

  it('lets either party open a dispute, before or after delivery', () => {
    for (const state of ['active', 'delivered'] as const) {
      expect(applyEvent(state, 'open_dispute', 'buyer').ok).toBe(true)
      expect(applyEvent(state, 'open_dispute', 'seller').ok).toBe(true)
    }
  })

  it('reports what each actor can do from a state', () => {
    expect(availableEventsFor('delivered', 'buyer').sort()).toEqual(
      ['confirm_delivery', 'open_dispute', 'request_revision'].sort(),
    )
    expect(availableEventsFor('delivered', 'seller')).toEqual(['open_dispute'])
    expect(availableEventsFor('delivered', 'system')).toEqual([])
  })
})

describe('lifecycle walkthroughs', () => {
  function walk(steps: readonly [TransactionEvent, Actor][]): TransactionState {
    let state: TransactionState = 'draft'
    for (const [event, actor] of steps) {
      state = unwrap(applyEvent(state, event, actor))
    }
    return state
  }

  it('completes the happy path', () => {
    expect(
      walk([
        ['submit', 'buyer'],
        ['accept', 'seller'],
        ['mark_delivered', 'seller'],
        ['confirm_delivery', 'buyer'],
      ]),
    ).toBe('completed')
  })

  it('supports a revision round before completion', () => {
    expect(
      walk([
        ['submit', 'buyer'],
        ['accept', 'seller'],
        ['mark_delivered', 'seller'],
        ['request_revision', 'buyer'],
        ['mark_delivered', 'seller'],
        ['confirm_delivery', 'buyer'],
      ]),
    ).toBe('completed')
  })

  it('routes a disputed delivery to resolution', () => {
    expect(
      walk([
        ['submit', 'buyer'],
        ['accept', 'seller'],
        ['mark_delivered', 'seller'],
        ['open_dispute', 'buyer'],
        ['resolve_dispute', 'system'],
      ]),
    ).toBe('resolved')
  })

  it('expires an ignored contract', () => {
    expect(walk([['submit', 'buyer'], ['expire', 'system']])).toBe('expired')
  })

  it('refuses to move once a contract is completed', () => {
    const completed = walk([
      ['submit', 'buyer'],
      ['accept', 'seller'],
      ['mark_delivered', 'seller'],
      ['confirm_delivery', 'buyer'],
    ])
    const result = applyEvent(completed, 'open_dispute', 'buyer')
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('TERMINAL_STATE')
  })
})

describe('toMermaid', () => {
  it('emits one edge per rule', () => {
    const diagram = toMermaid()
    expect(diagram.startsWith('stateDiagram-v2')).toBe(true)
    for (const rule of TRANSITIONS) {
      expect(diagram).toContain(`${rule.from} --> ${rule.to}: ${rule.event}`)
    }
  })
})

describe('the identity gate', () => {
  const both = { buyerVerified: true, sellerVerified: true }

  it('lets an accept through when both parties are verified', () => {
    expect(identityGate('accept', both, 'seller')).toBeNull()
  })

  it('blocks an accept while either party is unverified', () => {
    for (const verification of [
      { buyerVerified: false, sellerVerified: true },
      { buyerVerified: true, sellerVerified: false },
      { buyerVerified: false, sellerVerified: false },
    ]) {
      const error = identityGate('accept', verification, 'seller')
      expect(error, JSON.stringify(verification)).not.toBeNull()
      expect(error?.code).toBe('GUARD_FAILED')
    }
  })

  it('names who is missing, so the app can say something useful', () => {
    const error = identityGate('accept', { buyerVerified: false, sellerVerified: true }, 'buyer')
    expect(error?.message).toContain('buyer')
    expect(error?.message).not.toContain('seller.')
  })

  it('gates nothing but accept', () => {
    // Drafting, delivering and disputing stay open to an unverified party.
    // Only the moment a contract becomes binding requires verified identities.
    const unverified = { buyerVerified: false, sellerVerified: false }
    for (const event of TRANSACTION_EVENTS) {
      if (event === 'accept') continue
      expect(identityGate(event, unverified, 'buyer'), event).toBeNull()
    }
  })
})
