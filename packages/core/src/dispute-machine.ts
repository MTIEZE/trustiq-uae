/**
 * The dispute state machine.
 *
 * The product decision encoded here: the AI does not rule, it proposes. A
 * proposal only closes a dispute when BOTH parties accept it. A single refusal
 * escalates to a human. That keeps TrustIQ out of the business of imposing
 * binding financial decisions, which is a regulated and legally untested thing
 * to do, and it turns the acceptance rate into the metric that tells us whether
 * the model is actually any good.
 */

import { err, ok, type Result } from './result.js'
import {
  isTerminalDisputeState,
  type Actor,
  type DisputeEvent,
  type DisputeState,
  type Role,
  type TransitionError,
} from './types.js'

export interface DisputeTransitionRule {
  readonly from: DisputeState
  readonly event: DisputeEvent
  readonly to: DisputeState
  readonly actors: readonly Actor[]
  readonly describe: string
}

export const DISPUTE_TRANSITIONS: readonly DisputeTransitionRule[] = [
  {
    from: 'open',
    event: 'submit_for_ai',
    to: 'ai_review',
    actors: ['system'],
    describe: 'Both claims and the evidence bundle are complete, so the case goes to the model.',
  },
  {
    from: 'open',
    event: 'withdraw_dispute',
    to: 'withdrawn',
    actors: ['buyer', 'seller'],
    describe: 'The party who opened the dispute drops it, usually after settling directly.',
  },
  {
    from: 'ai_review',
    event: 'issue_proposal',
    to: 'proposal_issued',
    actors: ['system'],
    describe: 'The model returned a resolution that passed schema and confidence checks.',
  },
  {
    from: 'ai_review',
    event: 'escalate',
    to: 'escalated',
    actors: ['system'],
    describe:
      'Confidence was below threshold or the amount exceeded the automatic ceiling, so no proposal is shown.',
  },
  {
    from: 'proposal_issued',
    event: 'accept_proposal',
    to: 'accepted',
    actors: ['system'],
    describe: 'Both parties accepted. Fired by the system only once the second acceptance lands.',
  },
  {
    from: 'proposal_issued',
    event: 'reject_proposal',
    to: 'escalated',
    actors: ['buyer', 'seller'],
    describe: 'Either party refuses the proposal. One refusal is enough.',
  },
  {
    from: 'escalated',
    event: 'assign_reviewer',
    to: 'human_review',
    actors: ['system'],
    describe: 'A human reviewer picks up the case.',
  },
  {
    from: 'human_review',
    event: 'issue_human_resolution',
    to: 'resolved_by_human',
    actors: ['system'],
    describe: 'The reviewer issued a decision, closing the dispute.',
  },
]

const INDEX = new Map<string, DisputeTransitionRule>(
  DISPUTE_TRANSITIONS.map((rule) => [`${rule.from}::${rule.event}`, rule]),
)

export function canTransitionDispute(
  state: DisputeState,
  event: DisputeEvent,
  actor: Actor,
): boolean {
  const rule = INDEX.get(`${state}::${event}`)
  return rule !== undefined && rule.actors.includes(actor)
}

export function applyDisputeEvent(
  state: DisputeState,
  event: DisputeEvent,
  actor: Actor,
): Result<DisputeState, TransitionError> {
  if (isTerminalDisputeState(state)) {
    return err({
      code: 'TERMINAL_STATE',
      message: `Dispute is ${state} and can no longer change.`,
      from: state,
      event,
      actor,
    })
  }

  const rule = INDEX.get(`${state}::${event}`)
  if (rule === undefined) {
    return err({
      code: 'INVALID_TRANSITION',
      message: `"${event}" is not a legal move from ${state}.`,
      from: state,
      event,
      actor,
    })
  }

  if (!rule.actors.includes(actor)) {
    return err({
      code: 'ACTOR_NOT_PERMITTED',
      message: `The ${actor} may not fire "${event}" from ${state}. Allowed: ${rule.actors.join(', ')}.`,
      from: state,
      event,
      actor,
    })
  }

  return ok(rule.to)
}

export interface AcceptanceOutcome {
  /** Roles that have accepted after recording this one. */
  readonly acceptedBy: readonly Role[]
  /** True once both sides have accepted and the dispute may close. */
  readonly bothAccepted: boolean
}

/**
 * Record one party accepting the current proposal.
 *
 * Idempotent: the same role accepting twice does not count as two acceptances,
 * which matters because a retried network request must never close a dispute on
 * one party's say-so.
 */
export function recordAcceptance(
  acceptedBy: readonly Role[],
  role: Role,
): AcceptanceOutcome {
  const next = acceptedBy.includes(role) ? [...acceptedBy] : [...acceptedBy, role]
  return {
    acceptedBy: next,
    bothAccepted: next.includes('buyer') && next.includes('seller'),
  }
}

export function toMermaid(): string {
  const lines = ['stateDiagram-v2', '  [*] --> open']
  for (const rule of DISPUTE_TRANSITIONS) {
    lines.push(`  ${rule.from} --> ${rule.to}: ${rule.event}`)
  }
  return lines.join('\n')
}
