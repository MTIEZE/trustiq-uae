/**
 * The transaction state machine.
 *
 * Every legal move in a TrustIQ contract is one row in TRANSITIONS. Anything
 * not in the table is rejected. This is deliberately a data table rather than a
 * pile of `if` statements: it can be tested exhaustively, diffed in review, and
 * printed for a lawyer or a regulator who wants to know what the product can do.
 *
 * Each row also declares WHO may fire the event. In a trust product, "the buyer
 * confirmed delivery" is only meaningful if the seller could not have done it.
 */

import { err, ok, type Result } from './result.js'
import {
  isTerminalTransactionState,
  type Actor,
  type TransactionEvent,
  type TransactionState,
  type TransitionError,
} from './types.js'

export interface TransitionRule {
  readonly from: TransactionState
  readonly event: TransactionEvent
  readonly to: TransactionState
  /** Actors allowed to fire this event. */
  readonly actors: readonly Actor[]
  /** Plain-language description, surfaced in the audit log and in docs. */
  readonly describe: string
}

export const TRANSITIONS: readonly TransitionRule[] = [
  {
    from: 'draft',
    event: 'submit',
    to: 'pending_acceptance',
    actors: ['buyer', 'seller'],
    describe: 'The party who drafted the contract sends it to the other side.',
  },
  {
    from: 'draft',
    event: 'withdraw',
    to: 'cancelled',
    actors: ['buyer', 'seller'],
    describe: 'The drafting party abandons the contract before sending it.',
  },
  {
    from: 'pending_acceptance',
    event: 'accept',
    to: 'active',
    actors: ['buyer', 'seller'],
    describe: 'The receiving party agrees to the terms. The contract is now binding between them.',
  },
  {
    from: 'pending_acceptance',
    event: 'decline',
    to: 'declined',
    actors: ['buyer', 'seller'],
    describe: 'The receiving party refuses the terms.',
  },
  {
    from: 'pending_acceptance',
    event: 'withdraw',
    to: 'cancelled',
    actors: ['buyer', 'seller'],
    describe: 'The sending party pulls the contract back before it is accepted.',
  },
  {
    from: 'pending_acceptance',
    event: 'expire',
    to: 'expired',
    actors: ['system'],
    describe: 'The acceptance deadline passed with no answer.',
  },
  {
    from: 'active',
    event: 'mark_delivered',
    to: 'delivered',
    actors: ['seller'],
    describe: 'The seller declares the work delivered and hands review to the buyer.',
  },
  {
    from: 'active',
    event: 'open_dispute',
    to: 'disputed',
    actors: ['buyer', 'seller'],
    describe: 'Either party raises a problem before delivery is declared.',
  },
  {
    from: 'active',
    event: 'cancel_by_agreement',
    to: 'cancelled',
    actors: ['system'],
    describe: 'Both parties agreed to call the contract off. Fired by the system once both have confirmed.',
  },
  {
    from: 'delivered',
    event: 'confirm_delivery',
    to: 'completed',
    actors: ['buyer'],
    describe: 'The buyer accepts the delivery. The contract closes successfully.',
  },
  {
    from: 'delivered',
    event: 'request_revision',
    to: 'active',
    actors: ['buyer'],
    describe: 'The buyer sends the work back for changes without escalating to a dispute.',
  },
  {
    from: 'delivered',
    event: 'open_dispute',
    to: 'disputed',
    actors: ['buyer', 'seller'],
    describe: 'Review broke down and a formal dispute is opened.',
  },
  {
    from: 'disputed',
    event: 'resolve_dispute',
    to: 'resolved',
    actors: ['system'],
    describe:
      'The dispute reached a conclusion, either both parties accepting the AI proposal or a human reviewer deciding.',
  },
]

/** Index for O(1) lookup, built once at module load. */
const TRANSITION_INDEX = new Map<string, TransitionRule>(
  TRANSITIONS.map((rule) => [key(rule.from, rule.event), rule]),
)

function key(from: TransactionState, event: TransactionEvent): string {
  return `${from}::${event}`
}

/** Every event that is legal from a state, regardless of actor. */
export function availableEvents(state: TransactionState): TransactionEvent[] {
  return TRANSITIONS.filter((rule) => rule.from === state).map((rule) => rule.event)
}

/** Every event a specific actor may fire from a state. Drives what the UI shows. */
export function availableEventsFor(state: TransactionState, actor: Actor): TransactionEvent[] {
  return TRANSITIONS.filter((rule) => rule.from === state && rule.actors.includes(actor)).map(
    (rule) => rule.event,
  )
}

export function canTransition(
  state: TransactionState,
  event: TransactionEvent,
  actor: Actor,
): boolean {
  const rule = TRANSITION_INDEX.get(key(state, event))
  return rule !== undefined && rule.actors.includes(actor)
}

/**
 * Apply an event to a state.
 *
 * Returns the next state, or a typed error explaining precisely why the move was
 * refused. The distinction between INVALID_TRANSITION and ACTOR_NOT_PERMITTED
 * matters: the first is a bug or a stale client, the second is someone trying to
 * act as the other party and belongs in the audit log.
 */
export function applyEvent(
  state: TransactionState,
  event: TransactionEvent,
  actor: Actor,
): Result<TransactionState, TransitionError> {
  if (isTerminalTransactionState(state)) {
    return err({
      code: 'TERMINAL_STATE',
      message: `Transaction is ${state} and can no longer change.`,
      from: state,
      event,
      actor,
    })
  }

  const rule = TRANSITION_INDEX.get(key(state, event))
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

/** Render the machine as Mermaid, so the diagram can never drift from the code. */
export function toMermaid(): string {
  const lines = ['stateDiagram-v2', '  [*] --> draft']
  for (const rule of TRANSITIONS) {
    lines.push(`  ${rule.from} --> ${rule.to}: ${rule.event}`)
  }
  return lines.join('\n')
}
