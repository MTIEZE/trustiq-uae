/**
 * Running one dispute through the resolution pipeline and recording what
 * happened.
 *
 * The pipeline itself decides whether a case produces a proposal or goes to a
 * human. This file's job is the surrounding bookkeeping, and it holds one rule
 * the pipeline cannot enforce on its own:
 *
 *   No audit record, no proposal.
 *
 * If the audit write fails, the run escalates instead of showing the parties a
 * resolution nobody can later explain. An unexplainable decision about
 * someone's money is worse than a slow one.
 */

import { resolveDispute, type AuditRecord, type ModelClient } from '@trustiq/ai'
import type { EscalationPolicy, Fils } from '@trustiq/core'
import type { Clock, DisputeRepository } from './ports.js'

export type RunResult =
  | { readonly kind: 'proposal'; readonly proposalId: string; readonly disputeId: string }
  | { readonly kind: 'escalated'; readonly disputeId: string; readonly reason: string }
  | { readonly kind: 'skipped'; readonly disputeId: string; readonly reason: string }

export interface RunDeps {
  readonly repository: DisputeRepository
  readonly model: ModelClient
  readonly policy: EscalationPolicy
  readonly clock: Clock
}

export async function runResolution(disputeId: string, deps: RunDeps): Promise<RunResult> {
  const dispute = await deps.repository.loadCase(disputeId)
  if (dispute === null) {
    return { kind: 'skipped', disputeId, reason: 'dispute not found' }
  }

  // The amount is copied onto the dispute when it opens, but this run may have
  // been queued a while ago. If the two no longer agree, something changed
  // underneath us and the case should not be resolved from a stale figure.
  const current: Fils | null = await deps.repository.disputedAmount(disputeId)
  if (current === null || current !== dispute.disputedAmount) {
    const reason = `disputed amount changed since the case was loaded (${String(dispute.disputedAmount)} to ${String(current)})`
    await deps.repository.markEscalated(disputeId, reason)
    return { kind: 'escalated', disputeId, reason }
  }

  // The dispute has to reach `ai_review` before anything else can happen to
  // it: both `issue_proposal` and `escalate` are only legal from there. This
  // is also the state the parties see while the case is being read.
  try {
    await deps.repository.beginAnalysis(disputeId)
  } catch (error) {
    const reason = `the dispute could not be moved into review: ${describe(error)}`
    await deps.repository.markEscalated(disputeId, reason).catch(() => undefined)
    return { kind: 'escalated', disputeId, reason }
  }

  const outcome = await resolveDispute(dispute, deps.model, {
    policy: deps.policy,
    now: () => deps.clock.now(),
  })

  const audited = await recordAudit(outcome.audit, deps)
  if (!audited) {
    const reason = 'the audit record could not be written, so no proposal was issued'
    await deps.repository.markEscalated(disputeId, reason).catch(() => undefined)
    return { kind: 'escalated', disputeId, reason }
  }

  if (outcome.kind === 'escalate') {
    const reason = describeCause(outcome.cause)
    await deps.repository.markEscalated(disputeId, reason)
    return { kind: 'escalated', disputeId, reason }
  }

  try {
    const { proposalId } = await deps.repository.saveProposal({
      disputeId,
      proposal: outcome.proposal,
    })
    return { kind: 'proposal', proposalId, disputeId }
  } catch (error) {
    // The proposal was valid but could not be stored. The parties must not be
    // shown something the record does not contain, so this goes to a human too.
    const reason = `the proposal could not be stored: ${describe(error)}`
    await deps.repository.markEscalated(disputeId, reason).catch(() => undefined)
    return { kind: 'escalated', disputeId, reason }
  }
}

async function recordAudit(record: AuditRecord, deps: RunDeps): Promise<boolean> {
  try {
    await deps.repository.appendAuditRecord(record)
    return true
  } catch {
    return false
  }
}

/** A short, human-readable reason for the reviewer picking the case up. */
export function describeCause(cause: import('@trustiq/ai').EscalationCause): string {
  switch (cause.kind) {
    case 'model_refused':
      return `the model declined to answer${cause.category === null ? '' : ` (${cause.category})`}`
    case 'model_truncated':
      return 'the model response was cut off before it finished'
    case 'model_error':
      return `the model call failed: ${cause.message}`
    case 'malformed_output':
      return `the model returned unusable output: ${cause.detail}`
    case 'failed_validation':
      return `the proposal failed validation (${cause.code}): ${cause.detail}`
    case 'policy':
      return `policy requires human review: ${cause.reasons.join(', ')}`
  }
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
