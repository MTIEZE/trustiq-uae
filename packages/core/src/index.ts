/**
 * @trustiq/core
 *
 * Framework-agnostic domain logic for TrustIQ: money, the transaction and
 * dispute lifecycles, and the AI resolution contract. No React, no network, no
 * database. Everything here is pure and exhaustively tested, so the same rules
 * run identically in the web app, the mobile app, and on the server.
 */

export * from './money.js'
export * from './result.js'
export * from './types.js'
export * from './resolution.js'

export {
  TRANSITIONS,
  applyEvent,
  availableEvents,
  availableEventsFor,
  canTransition,
  toMermaid as transactionMermaid,
  type TransitionRule,
} from './transaction-machine.js'

export {
  DISPUTE_TRANSITIONS,
  applyDisputeEvent,
  canTransitionDispute,
  recordAcceptance,
  toMermaid as disputeMermaid,
  type AcceptanceOutcome,
  type DisputeTransitionRule,
} from './dispute-machine.js'
