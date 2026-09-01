import { describe, expect, it } from 'vitest'
import { fils, filsFromAed, splitByPercent, type Fils } from './money.js'
import {
  escalationReasons,
  shouldEscalate,
  validateProposal,
  type EscalationPolicy,
  type ResolutionProposal,
} from './resolution.js'
import type { EvidenceId } from './types.js'

const CONTRACT = 'ev_contract' as EvidenceId
const DELIVERY = 'ev_delivery' as EvidenceId
const KNOWN = [CONTRACT, DELIVERY]

const DISPUTED = filsFromAed('500')

function proposal(overrides: Partial<ResolutionProposal> = {}): ResolutionProposal {
  const split = splitByPercent(DISPUTED, 60)
  return {
    decision: 'split',
    summary: 'Delivery happened on time but quality could not be verified from the evidence.',
    findings: [
      { statement: 'A signed contract exists dated June 1.', evidenceIds: [CONTRACT], citesTerms: false },
      { statement: 'Delivery was made on June 8, inside the agreed window.', evidenceIds: [DELIVERY], citesTerms: false },
    ],
    allocation: { seller: split.seller, buyer: split.buyer },
    confidence: 0.62,
    modelId: 'claude-sonnet-5',
    issuedAt: '2026-08-18T10:00:00.000Z',
    ...overrides,
  }
}

const context = { disputedAmount: DISPUTED, knownEvidenceIds: KNOWN }

describe('validateProposal', () => {
  it('accepts a well-formed, grounded proposal', () => {
    const result = validateProposal(proposal(), context)
    expect(result.ok).toBe(true)
  })

  it('rejects an allocation that does not sum to the disputed amount', () => {
    // One fil short. This is the failure that silently unbalances a ledger,
    // so it must be caught before a human ever sees the proposal.
    const short = proposal({ allocation: { seller: fils(30_000), buyer: fils(19_999) } })
    const result = validateProposal(short, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('ALLOCATION_MISMATCH')
  })

  it('rejects an allocation that invents money', () => {
    const over = proposal({ allocation: { seller: fils(30_000), buyer: fils(20_001) } })
    const result = validateProposal(over, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('ALLOCATION_MISMATCH')
  })

  it('rejects negative shares', () => {
    const negative = proposal({ allocation: { seller: fils(60_000), buyer: fils(-10_000) } })
    const result = validateProposal(negative, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('NEGATIVE_ALLOCATION')
  })

  it('rejects a decision that contradicts its own allocation', () => {
    const conflicting = proposal({
      decision: 'refund_to_buyer',
      allocation: { seller: fils(30_000), buyer: fils(20_000) },
    })
    const result = validateProposal(conflicting, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('DECISION_ALLOCATION_CONFLICT')
  })

  it('rejects a split that is not actually a split', () => {
    const notASplit = proposal({
      decision: 'split',
      allocation: { seller: DISPUTED, buyer: fils(0) },
    })
    const result = validateProposal(notASplit, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('DECISION_ALLOCATION_CONFLICT')
  })

  it('accepts the clean one-sided decisions', () => {
    const toSeller = proposal({
      decision: 'release_to_seller',
      allocation: { seller: DISPUTED, buyer: fils(0) },
    })
    expect(validateProposal(toSeller, context).ok).toBe(true)

    const toBuyer = proposal({
      decision: 'refund_to_buyer',
      allocation: { seller: fils(0), buyer: DISPUTED },
    })
    expect(validateProposal(toBuyer, context).ok).toBe(true)
  })

  it('rejects confidence outside 0 to 1', () => {
    for (const confidence of [-0.1, 1.1, Number.NaN]) {
      const result = validateProposal(proposal({ confidence }), context)
      expect(result.ok).toBe(false)
      if (!result.ok) expect(result.error.code).toBe('CONFIDENCE_OUT_OF_RANGE')
    }
  })

  it('rejects a resolution that does not explain itself', () => {
    const result = validateProposal(proposal({ summary: '   ' }), context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('EMPTY_SUMMARY')
  })

  it('rejects a finding that rests on nothing at all', () => {
    const ungrounded = proposal({
      findings: [
        { statement: 'The work was clearly substandard.', evidenceIds: [], citesTerms: false },
      ],
    })
    const result = validateProposal(ungrounded, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('UNGROUNDED_FINDING')
  })

  it('accepts a finding that rests on the agreed terms alone', () => {
    // What the agreement required is usually the most important line in a
    // dispute, and it was uncitable: only filed documents carried ids, so the
    // model either dropped the point or had the whole proposal refused. Ten
    // live runs on 1 September 2026 were refused for exactly this.
    const onTerms = proposal({
      findings: [
        {
          statement: 'The agreement set no deadline, so late delivery cannot be a breach of it.',
          evidenceIds: [],
          citesTerms: true,
        },
      ],
    })
    expect(validateProposal(onTerms, context).ok).toBe(true)
  })

  it('still refuses invented evidence on a finding that also rests on the terms', () => {
    // The looser rule must not become a way in. Citing the agreement does not
    // excuse a document that was never filed.
    const both = proposal({
      findings: [
        {
          statement: 'The agreement required a report, and one was filed.',
          evidenceIds: ['ev_ghost' as EvidenceId],
          citesTerms: true,
        },
      ],
    })
    const result = validateProposal(both, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('UNKNOWN_EVIDENCE')
  })

  it('rejects a finding that cites evidence nobody submitted', () => {
    const hallucinated = proposal({
      findings: [
        { statement: 'An email from June 3 confirms the change.', evidenceIds: ['ev_ghost' as EvidenceId], citesTerms: false },
      ],
    })
    const result = validateProposal(hallucinated, context)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error.code).toBe('UNKNOWN_EVIDENCE')
  })

  it('conserves the amount for every whole-percentage split the model could pick', () => {
    for (let pct = 0; pct <= 100; pct++) {
      const split = splitByPercent(DISPUTED, pct)
      const decision = pct === 100 ? 'release_to_seller' : pct === 0 ? 'refund_to_buyer' : 'split'
      const result = validateProposal(
        proposal({ decision, allocation: { seller: split.seller, buyer: split.buyer } }),
        context,
      )
      expect(result.ok, `split at ${pct}% was rejected`).toBe(true)
    }
  })
})

describe('escalation policy', () => {
  const policy: EscalationPolicy = {
    minConfidence: 0.7,
    maxAutoAmount: filsFromAed('5000'),
  }

  it('escalates when the model is not confident enough', () => {
    const reasons = escalationReasons(proposal({ confidence: 0.5 }), DISPUTED, policy)
    expect(reasons).toEqual(['low_confidence'])
    expect(shouldEscalate(proposal({ confidence: 0.5 }), DISPUTED, policy)).toBe(true)
  })

  it('escalates above the automatic ceiling even when confident', () => {
    const big = filsFromAed('50000') as Fils
    const reasons = escalationReasons(proposal({ confidence: 0.99 }), big, policy)
    expect(reasons).toEqual(['amount_above_ceiling'])
  })

  it('reports both reasons when both apply', () => {
    const big = filsFromAed('50000') as Fils
    const reasons = escalationReasons(proposal({ confidence: 0.1 }), big, policy)
    expect(reasons).toEqual(['low_confidence', 'amount_above_ceiling'])
  })

  it('lets a confident proposal on a small amount through', () => {
    expect(shouldEscalate(proposal({ confidence: 0.85 }), DISPUTED, policy)).toBe(false)
  })

  it('treats the thresholds as inclusive boundaries', () => {
    expect(shouldEscalate(proposal({ confidence: 0.7 }), DISPUTED, policy)).toBe(false)
    expect(shouldEscalate(proposal({ confidence: 0.85 }), policy.maxAutoAmount, policy)).toBe(false)
  })

  it('escalates the demo case from the landing page, which is medium confidence', () => {
    // The demo shows a 60/40 split with "Medium" confidence. Under this policy
    // that case would go to a human, which is the correct behaviour and worth
    // pinning down before the marketing copy promises otherwise.
    expect(shouldEscalate(proposal({ confidence: 0.62 }), DISPUTED, policy)).toBe(true)
  })
})
