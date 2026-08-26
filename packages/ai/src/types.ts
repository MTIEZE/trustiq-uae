/**
 * Inputs and outputs for the dispute resolution pipeline.
 *
 * The pipeline is written against these interfaces rather than against a
 * database or an HTTP client, so the whole thing runs in tests with no network
 * and no Supabase. The only impure edge is ModelClient.
 */

import type { EscalationPolicy, EvidenceId, Fils, ResolutionProposal } from '@trustiq/core'

/** One piece of evidence, as the model will see it. */
export interface EvidenceSummary {
  readonly id: EvidenceId
  readonly uploadedByRole: 'buyer' | 'seller'
  readonly filename: string
  readonly contentType: string
  readonly uploadedAt: string
  readonly sha256: string
  /** Free-text note the uploader attached. Null when they left it blank. */
  readonly note: string | null
  /**
   * Text the pipeline was able to extract from the file, when it could.
   *
   * v1 sends only what it can read as text. Nothing here is trusted as
   * instruction: it is quoted into the prompt as evidence content, and the
   * system prompt tells the model to treat it as material under dispute.
   */
  readonly extractedText: string | null
  /**
   * Why `extractedText` is present or absent.
   *
   * Carried separately because the reasons are not equivalent. A photograph
   * has no text to read; a file that failed extraction has content the model
   * is not seeing, and that is a reason to be less confident rather than a
   * neutral absence. `truncated` says the text is the start of the document
   * and not the whole of it, and it lives here rather than as a marker inside
   * the text because a party could type that marker themselves.
   */
  readonly extractionStatus: 'not_attempted' | 'unsupported' | 'failed' | 'extracted' | 'truncated'
}

export interface DisputeCase {
  readonly disputeId: string
  readonly transactionId: string
  readonly description: string
  readonly terms: string
  readonly disputedAmount: Fils
  readonly buyerClaim: string
  readonly sellerClaim: string | null
  readonly evidence: readonly EvidenceSummary[]
  /** ISO timestamps, for reasoning about whether delivery was on time. */
  readonly contractAcceptedAt: string | null
  readonly deliveredAt: string | null
  readonly disputeOpenedAt: string
}

/* ------------------------------------------------------------------ *
 * The model boundary
 * ------------------------------------------------------------------ */

export interface ModelRequest {
  readonly system: string
  readonly userContent: string
  /** JSON Schema the response must conform to. */
  readonly schema: Record<string, unknown>
}

export type ModelOutcome =
  | { readonly kind: 'completed'; readonly json: string; readonly modelId: string; readonly latencyMs: number }
  /** The model's safety classifiers declined. Never treated as a resolution. */
  | { readonly kind: 'refused'; readonly category: string | null; readonly modelId: string; readonly latencyMs: number }
  /** The response hit the output cap before finishing. The JSON is unusable. */
  | { readonly kind: 'truncated'; readonly modelId: string; readonly latencyMs: number }
  | { readonly kind: 'error'; readonly message: string; readonly retryable: boolean; readonly latencyMs: number }

export interface ModelClient {
  readonly modelId: string
  readonly promptVersion: string
  complete(request: ModelRequest): Promise<ModelOutcome>
}

/* ------------------------------------------------------------------ *
 * The pipeline's result
 * ------------------------------------------------------------------ */

/**
 * Why a case did not produce a proposal the parties can see.
 *
 * Every one of these routes to a human. None of them is an excuse to show the
 * parties something unvalidated.
 */
export type EscalationCause =
  | { readonly kind: 'model_refused'; readonly category: string | null }
  | { readonly kind: 'model_truncated' }
  | { readonly kind: 'model_error'; readonly message: string; readonly retryable: boolean }
  | { readonly kind: 'malformed_output'; readonly detail: string }
  | { readonly kind: 'failed_validation'; readonly code: string; readonly detail: string }
  | { readonly kind: 'policy'; readonly reasons: readonly string[] }

export type ResolutionOutcome =
  | { readonly kind: 'proposal'; readonly proposal: ResolutionProposal; readonly audit: AuditRecord }
  | { readonly kind: 'escalate'; readonly cause: EscalationCause; readonly audit: AuditRecord }

/**
 * One row for public.ai_call_log.
 *
 * Written on every path, including refusals and validation failures. A model
 * that fails validation often is a signal, and deleting the failures hides it.
 */
export interface AuditRecord {
  readonly disputeId: string
  readonly modelId: string
  readonly promptVersion: string
  readonly requestPayload: Record<string, unknown>
  readonly responsePayload: Record<string, unknown> | null
  readonly confidence: number | null
  /** 'accepted', or the reason it was refused. Mirrors ai_call_log.validation_outcome. */
  readonly validationOutcome: string
  readonly escalationReasons: readonly string[]
  readonly latencyMs: number
  readonly errorMessage: string | null
}

export interface ResolveOptions {
  readonly policy: EscalationPolicy
  /** Injected so tests and the audit log agree on the time. */
  readonly now: () => Date
}
