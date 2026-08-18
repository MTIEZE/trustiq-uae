/**
 * The contract between the AI resolution engine and the rest of the product.
 *
 * The model is never trusted. Everything it returns passes through
 * `validateProposal` before a human ever sees it, and a proposal that fails
 * validation is escalated rather than shown. The invariant that matters most:
 * the allocation must sum to exactly the disputed amount, to the fil. A model
 * that quietly loses 1 fil on a 500 AED split has created an unbalanced ledger
 * entry, and at volume that becomes a reconciliation problem nobody can unwind.
 */

import { add, isPositive, type Fils } from './money.js'
import { err, ok, type Result } from './result.js'
import type { EvidenceId } from './types.js'

export const RESOLUTION_DECISIONS = [
  'release_to_seller',
  'refund_to_buyer',
  'split',
] as const

export type ResolutionDecision = (typeof RESOLUTION_DECISIONS)[number]

export interface Allocation {
  readonly seller: Fils
  readonly buyer: Fils
}

/**
 * A single grounded claim in the model's reasoning.
 *
 * Requiring evidence references is what separates a resolution from an opinion.
 * If the model cannot point at the document that supports a statement, that
 * statement does not belong in a decision about someone's money.
 */
export interface GroundedFinding {
  readonly statement: string
  readonly evidenceIds: readonly EvidenceId[]
}

export interface ResolutionProposal {
  readonly decision: ResolutionDecision
  readonly summary: string
  readonly findings: readonly GroundedFinding[]
  readonly allocation: Allocation
  /** 0 to 1 inclusive. Drives the escalation threshold, so it must be a number, not a word. */
  readonly confidence: number
  /** Exact model identifier, recorded for the audit trail. */
  readonly modelId: string
  readonly issuedAt: string
}

export type ProposalRejectionCode =
  | 'ALLOCATION_MISMATCH'
  | 'NEGATIVE_ALLOCATION'
  | 'DECISION_ALLOCATION_CONFLICT'
  | 'CONFIDENCE_OUT_OF_RANGE'
  | 'EMPTY_SUMMARY'
  | 'UNGROUNDED_FINDING'
  | 'UNKNOWN_EVIDENCE'

export interface ProposalRejection {
  readonly code: ProposalRejectionCode
  readonly message: string
}

export interface ValidationContext {
  /** The amount under dispute. The allocation must sum to exactly this. */
  readonly disputedAmount: Fils
  /** Evidence actually attached to the dispute. Citations outside this set are hallucinations. */
  readonly knownEvidenceIds: readonly EvidenceId[]
}

export function validateProposal(
  proposal: ResolutionProposal,
  context: ValidationContext,
): Result<ResolutionProposal, ProposalRejection> {
  const { seller, buyer } = proposal.allocation

  if (seller < 0 || buyer < 0) {
    return err({
      code: 'NEGATIVE_ALLOCATION',
      message: `Allocation cannot be negative (seller ${seller}, buyer ${buyer}).`,
    })
  }

  const allocated = add(seller, buyer)
  if (allocated !== context.disputedAmount) {
    return err({
      code: 'ALLOCATION_MISMATCH',
      message: `Allocation sums to ${allocated} fils but the disputed amount is ${context.disputedAmount} fils.`,
    })
  }

  const conflict = decisionConflict(proposal.decision, proposal.allocation)
  if (conflict !== null) {
    return err({ code: 'DECISION_ALLOCATION_CONFLICT', message: conflict })
  }

  if (!Number.isFinite(proposal.confidence) || proposal.confidence < 0 || proposal.confidence > 1) {
    return err({
      code: 'CONFIDENCE_OUT_OF_RANGE',
      message: `Confidence must be between 0 and 1, got ${proposal.confidence}.`,
    })
  }

  if (proposal.summary.trim().length === 0) {
    return err({ code: 'EMPTY_SUMMARY', message: 'A resolution must explain itself.' })
  }

  const known = new Set<string>(context.knownEvidenceIds)
  for (const finding of proposal.findings) {
    if (finding.evidenceIds.length === 0) {
      return err({
        code: 'UNGROUNDED_FINDING',
        message: `Finding "${truncate(finding.statement)}" cites no evidence.`,
      })
    }
    for (const id of finding.evidenceIds) {
      if (!known.has(id)) {
        return err({
          code: 'UNKNOWN_EVIDENCE',
          message: `Finding "${truncate(finding.statement)}" cites evidence ${id}, which is not attached to this dispute.`,
        })
      }
    }
  }

  return ok(proposal)
}

function decisionConflict(decision: ResolutionDecision, allocation: Allocation): string | null {
  const sellerGetsAll = allocation.buyer === 0 && isPositive(allocation.seller)
  const buyerGetsAll = allocation.seller === 0 && isPositive(allocation.buyer)

  switch (decision) {
    case 'release_to_seller':
      return sellerGetsAll
        ? null
        : 'Decision is release_to_seller but the buyer receives a share.'
    case 'refund_to_buyer':
      return buyerGetsAll ? null : 'Decision is refund_to_buyer but the seller receives a share.'
    case 'split':
      return isPositive(allocation.seller) && isPositive(allocation.buyer)
        ? null
        : 'Decision is split but one side receives nothing.'
  }
}

function truncate(text: string, max = 60): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}...`
}

/* ------------------------------------------------------------------ *
 * Escalation policy
 * ------------------------------------------------------------------ */

export interface EscalationPolicy {
  /** Below this confidence, a human decides instead of the model. */
  readonly minConfidence: number
  /** Above this amount, a human always reviews regardless of confidence. */
  readonly maxAutoAmount: Fils
}

export type EscalationReason = 'low_confidence' | 'amount_above_ceiling'

/**
 * Decide whether a valid proposal may be shown to the parties, or must go
 * straight to a human.
 *
 * Both thresholds exist on purpose. Confidence guards against the model being
 * unsure; the amount ceiling guards against the model being confidently wrong
 * about a sum large enough to matter.
 */
export function escalationReasons(
  proposal: ResolutionProposal,
  disputedAmount: Fils,
  policy: EscalationPolicy,
): EscalationReason[] {
  const reasons: EscalationReason[] = []
  if (proposal.confidence < policy.minConfidence) reasons.push('low_confidence')
  if (disputedAmount > policy.maxAutoAmount) reasons.push('amount_above_ceiling')
  return reasons
}

export function shouldEscalate(
  proposal: ResolutionProposal,
  disputedAmount: Fils,
  policy: EscalationPolicy,
): boolean {
  return escalationReasons(proposal, disputedAmount, policy).length > 0
}
