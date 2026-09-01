/**
 * The dispute resolution pipeline.
 *
 * Every path through this function produces an AuditRecord, including the
 * failures. A model that refuses often, or fails validation often, is a signal
 * about the product; discarding those runs hides it.
 *
 * Nothing the model returns reaches a party without passing validateProposal
 * and the escalation policy first.
 */

import {
  escalationReasons,
  isErr,
  splitByPercent,
  validateProposal,
  type EvidenceId,
  type GroundedFinding,
  type ResolutionDecision,
  type ResolutionProposal,
} from '@trustiq/core'

import { SYSTEM_PROMPT, buildUserContent } from './prompt.js'
import { RESOLUTION_SCHEMA, type RawResolution } from './schema.js'
import type {
  AuditRecord,
  DisputeCase,
  EscalationCause,
  ModelClient,
  ModelOutcome,
  ResolutionOutcome,
  ResolveOptions,
} from './types.js'

export async function resolveDispute(
  dispute: DisputeCase,
  client: ModelClient,
  options: ResolveOptions,
): Promise<ResolutionOutcome> {
  const userContent = buildUserContent(dispute)
  const requestPayload = {
    system: SYSTEM_PROMPT,
    userContent,
    disputedAmountFils: dispute.disputedAmount,
    evidenceCount: dispute.evidence.length,
  }

  const audit = (over: Partial<AuditRecord>): AuditRecord => ({
    disputeId: dispute.disputeId,
    modelId: client.modelId,
    promptVersion: client.promptVersion,
    requestPayload,
    responsePayload: null,
    confidence: null,
    validationOutcome: 'accepted',
    escalationReasons: [],
    latencyMs: 0,
    errorMessage: null,
    ...over,
  })

  const escalate = (cause: EscalationCause, record: AuditRecord): ResolutionOutcome => ({
    kind: 'escalate',
    cause,
    audit: record,
  })

  let outcome: ModelOutcome
  try {
    outcome = await client.complete({ system: SYSTEM_PROMPT, userContent, schema: RESOLUTION_SCHEMA })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return escalate(
      { kind: 'model_error', message, retryable: false },
      audit({ validationOutcome: 'MODEL_THREW', errorMessage: message }),
    )
  }

  if (outcome.kind === 'refused') {
    return escalate(
      { kind: 'model_refused', category: outcome.category },
      audit({
        validationOutcome: 'MODEL_REFUSED',
        latencyMs: outcome.latencyMs,
        errorMessage: outcome.category,
      }),
    )
  }

  if (outcome.kind === 'truncated') {
    return escalate(
      { kind: 'model_truncated' },
      audit({
        validationOutcome: 'MODEL_TRUNCATED',
        latencyMs: outcome.latencyMs,
        errorMessage: 'response hit the output cap before completing',
      }),
    )
  }

  if (outcome.kind === 'error') {
    return escalate(
      { kind: 'model_error', message: outcome.message, retryable: outcome.retryable },
      audit({
        validationOutcome: 'MODEL_ERROR',
        latencyMs: outcome.latencyMs,
        errorMessage: outcome.message,
      }),
    )
  }

  const latencyMs = outcome.latencyMs

  let raw: RawResolution
  try {
    raw = JSON.parse(outcome.json) as RawResolution
  } catch {
    return escalate(
      { kind: 'malformed_output', detail: 'response was not valid JSON' },
      audit({
        validationOutcome: 'MALFORMED_JSON',
        latencyMs,
        errorMessage: outcome.json.slice(0, 500),
      }),
    )
  }

  const shapeError = checkShape(raw)
  if (shapeError !== null) {
    return escalate(
      { kind: 'malformed_output', detail: shapeError },
      audit({
        validationOutcome: 'MALFORMED_SHAPE',
        responsePayload: raw as unknown as Record<string, unknown>,
        latencyMs,
        errorMessage: shapeError,
      }),
    )
  }

  // Does the model's own label agree with its own number? A mismatch here is
  // the model contradicting itself, which is worth escalating.
  if (raw.decision !== decisionFromPercent(raw.sellerPercent)) {
    const detail = `decision "${raw.decision}" contradicts sellerPercent ${raw.sellerPercent}`
    return escalate(
      { kind: 'malformed_output', detail },
      audit({
        validationOutcome: 'DECISION_PERCENT_CONFLICT',
        responsePayload: raw as unknown as Record<string, unknown>,
        confidence: raw.confidence,
        latencyMs,
        errorMessage: detail,
      }),
    )
  }

  // The model chose a percentage; the code turns it into money. This is the
  // step that makes a lost fil impossible rather than merely detectable.
  const split = splitByPercent(dispute.disputedAmount, raw.sellerPercent)

  const proposal: ResolutionProposal = {
    // Derived from the money actually allocated, not from the model's label.
    // On a small enough amount a nonzero percentage rounds to zero fils, and
    // calling that outcome a "split" would tell one party they are getting a
    // share when they are getting nothing.
    decision: decisionFromAllocation(split.seller, split.buyer),
    summary: raw.summary,
    findings: raw.findings.map<GroundedFinding>((finding) => ({
      statement: finding.statement,
      evidenceIds: finding.evidenceIds as EvidenceId[],
      citesTerms: finding.citesTerms,
    })),
    allocation: { seller: split.seller, buyer: split.buyer },
    confidence: raw.confidence,
    modelId: outcome.modelId,
    issuedAt: options.now().toISOString(),
  }

  const responsePayload = {
    ...(raw as unknown as Record<string, unknown>),
    derivedAllocation: { seller: split.seller, buyer: split.buyer },
  }

  const validated = validateProposal(proposal, {
    disputedAmount: dispute.disputedAmount,
    knownEvidenceIds: dispute.evidence.map((item) => item.id),
  })

  if (isErr(validated)) {
    return escalate(
      { kind: 'failed_validation', code: validated.error.code, detail: validated.error.message },
      audit({
        validationOutcome: validated.error.code,
        responsePayload,
        confidence: raw.confidence,
        latencyMs,
        errorMessage: validated.error.message,
      }),
    )
  }

  const reasons = escalationReasons(proposal, dispute.disputedAmount, options.policy)
  if (reasons.length > 0) {
    return escalate(
      { kind: 'policy', reasons },
      audit({
        validationOutcome: 'ESCALATED_BY_POLICY',
        responsePayload,
        confidence: raw.confidence,
        escalationReasons: reasons,
        latencyMs,
      }),
    )
  }

  return {
    kind: 'proposal',
    proposal,
    audit: audit({
      validationOutcome: 'accepted',
      responsePayload,
      confidence: raw.confidence,
      latencyMs,
    }),
  }
}

function decisionFromPercent(percent: number): ResolutionDecision {
  if (percent === 100) return 'release_to_seller'
  if (percent === 0) return 'refund_to_buyer'
  return 'split'
}

function decisionFromAllocation(seller: number, buyer: number): ResolutionDecision {
  if (buyer === 0) return 'release_to_seller'
  if (seller === 0) return 'refund_to_buyer'
  return 'split'
}

/**
 * Structural checks the JSON Schema cannot express.
 *
 * Structured outputs guarantee the shape and the decision enum, but not that
 * `sellerPercent` is inside 0-100 or that the arrays hold the right primitives.
 * Anything wrong here means the output is unusable, not merely unconvincing.
 */
function checkShape(raw: RawResolution): string | null {
  if (!Number.isInteger(raw.sellerPercent) || raw.sellerPercent < 0 || raw.sellerPercent > 100) {
    return `sellerPercent must be a whole number between 0 and 100, got ${String(raw.sellerPercent)}`
  }
  if (typeof raw.confidence !== 'number' || Number.isNaN(raw.confidence)) {
    return `confidence must be a number, got ${String(raw.confidence)}`
  }
  if (typeof raw.summary !== 'string') {
    return 'summary must be a string'
  }
  if (!Array.isArray(raw.findings)) {
    return 'findings must be an array'
  }
  for (const [index, finding] of raw.findings.entries()) {
    if (typeof finding?.statement !== 'string') {
      return `findings[${index}].statement must be a string`
    }
    if (!Array.isArray(finding.evidenceIds) || finding.evidenceIds.some((id) => typeof id !== 'string')) {
      return `findings[${index}].evidenceIds must be an array of strings`
    }
    // Checked rather than coerced. A missing flag read as false would turn a
    // finding the model meant to rest on the agreement into an unsupported
    // one, and the proposal would be thrown away for the wrong reason.
    if (typeof finding.citesTerms !== 'boolean') {
      return `findings[${index}].citesTerms must be a boolean`
    }
  }
  return null
}
