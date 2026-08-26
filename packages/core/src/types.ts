/**
 * Core domain vocabulary for TrustIQ.
 *
 * Scope note: this models v1, which does NOT hold funds. A transaction is a
 * digital contract plus a delivery and dispute lifecycle; the payment happens
 * between the parties off-platform. Where v2 will introduce escrow states, the
 * code carries an ESCROW-V2 marker so the seam is visible rather than implied.
 */

import type { Fils } from './money.js'

/** Opaque identifiers. Branding stops a userId being passed as a transactionId. */
export type UserId = string & { readonly __brand: 'UserId' }
export type TransactionId = string & { readonly __brand: 'TransactionId' }
export type MilestoneId = string & { readonly __brand: 'MilestoneId' }
export type EvidenceId = string & { readonly __brand: 'EvidenceId' }
export type DisputeId = string & { readonly __brand: 'DisputeId' }

/** The two sides of a transaction. Roles are fixed for the life of the contract. */
export type Role = 'buyer' | 'seller'

/**
 * Who is attempting a transition.
 *
 * `system` covers timers, the AI pipeline, and internal reconciliation. It is
 * never a user, and transitions reserved for `system` can never be triggered
 * from a client request.
 */
export type Actor = Role | 'system'

export function counterpartyOf(role: Role): Role {
  return role === 'buyer' ? 'seller' : 'buyer'
}

export interface Party {
  readonly userId: UserId
  readonly role: Role
  /** Set once identity is verified (UAE Pass in production). Unverified parties can draft but not accept. */
  readonly identityVerified: boolean
}

export interface Milestone {
  readonly id: MilestoneId
  readonly title: string
  readonly amount: Fils
  readonly dueAt: string | null
  readonly deliveredAt: string | null
  readonly acceptedAt: string | null
}

/**
 * A piece of evidence attached to a transaction.
 *
 * `sha256` is the hash of the stored file, recorded at upload time. It is what
 * lets either party prove, later, that a document was not swapped after the
 * fact. Without it the evidence vault is just file storage.
 */
export interface Evidence {
  readonly id: EvidenceId
  readonly transactionId: TransactionId
  readonly uploadedBy: UserId
  readonly uploadedByRole: Role
  readonly filename: string
  readonly contentType: string
  readonly byteSize: number
  readonly sha256: string
  readonly uploadedAt: string
  readonly note: string | null
}

export interface Transaction {
  readonly id: TransactionId
  readonly state: TransactionState
  readonly buyer: Party
  readonly seller: Party
  readonly description: string
  readonly terms: string
  readonly totalAmount: Fils
  readonly milestones: readonly Milestone[]
  readonly createdBy: UserId
  readonly createdAt: string
  readonly acceptanceDeadline: string | null
  readonly stateChangedAt: string
}

/* ------------------------------------------------------------------ *
 * Transaction lifecycle
 * ------------------------------------------------------------------ */

export const TRANSACTION_STATES = [
  'draft',
  'pending_acceptance',
  'active',
  'delivered',
  'completed',
  'disputed',
  'resolved',
  'declined',
  'cancelled',
  'expired',
  // ESCROW-V2: 'funding_pending' and 'funds_held' slot between
  // 'pending_acceptance' and 'active' once a licensed partner holds funds.
] as const

export type TransactionState = (typeof TRANSACTION_STATES)[number]

export const TERMINAL_TRANSACTION_STATES = [
  'completed',
  'resolved',
  'declined',
  'cancelled',
  'expired',
] as const satisfies readonly TransactionState[]

export type TerminalTransactionState = (typeof TERMINAL_TRANSACTION_STATES)[number]

export function isTerminalTransactionState(state: TransactionState): state is TerminalTransactionState {
  return (TERMINAL_TRANSACTION_STATES as readonly TransactionState[]).includes(state)
}

export const TRANSACTION_EVENTS = [
  'submit',
  'withdraw',
  'accept',
  'decline',
  'expire',
  'mark_delivered',
  'request_revision',
  'confirm_delivery',
  'open_dispute',
  'resolve_dispute',
  'cancel_by_agreement',
] as const

export type TransactionEvent = (typeof TRANSACTION_EVENTS)[number]

/* ------------------------------------------------------------------ *
 * Dispute lifecycle
 * ------------------------------------------------------------------ */

export const DISPUTE_STATES = [
  'open',
  'ai_review',
  'proposal_issued',
  'accepted',
  'escalated',
  'human_review',
  'resolved_by_human',
  'withdrawn',
] as const

export type DisputeState = (typeof DISPUTE_STATES)[number]

export const TERMINAL_DISPUTE_STATES = [
  'accepted',
  'resolved_by_human',
  'withdrawn',
] as const satisfies readonly DisputeState[]

export function isTerminalDisputeState(state: DisputeState): boolean {
  return (TERMINAL_DISPUTE_STATES as readonly DisputeState[]).includes(state)
}

export const DISPUTE_EVENTS = [
  'submit_for_ai',
  'issue_proposal',
  'accept_proposal',
  'reject_proposal',
  'escalate',
  'assign_reviewer',
  'issue_human_resolution',
  'withdraw_dispute',
] as const

export type DisputeEvent = (typeof DISPUTE_EVENTS)[number]

export interface Dispute {
  readonly id: DisputeId
  readonly transactionId: TransactionId
  readonly state: DisputeState
  readonly openedBy: UserId
  readonly openedByRole: Role
  readonly buyerClaim: string
  readonly sellerClaim: string | null
  readonly evidenceIds: readonly EvidenceId[]
  readonly openedAt: string
  /** Roles that have accepted the current proposal. Both are required to close. */
  readonly acceptedBy: readonly Role[]
}

/* ------------------------------------------------------------------ *
 * Transition failures
 * ------------------------------------------------------------------ */

export type TransitionErrorCode =
  | 'INVALID_TRANSITION'
  | 'ACTOR_NOT_PERMITTED'
  | 'TERMINAL_STATE'
  | 'GUARD_FAILED'

export interface TransitionError {
  readonly code: TransitionErrorCode
  readonly message: string
  readonly from: string
  readonly event: string
  readonly actor: Actor
}
