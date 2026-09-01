/**
 * The Supabase-backed implementations of the ports.
 *
 * Thin by design: every rule already lives in the schema or in the domain
 * packages, so these translate and nothing more. Where a rule looks like it is
 * being decided here, it is being read back from the database that decided it.
 */

import type { SupabaseClient } from '@supabase/supabase-js'
import type { EvidenceId, Fils, Role } from '@trustiq/core'
import type { AuditRecord, DisputeCase } from '@trustiq/ai'

import type {
  DisputeRepository,
  EvidenceRepository,
  NewEvidenceRow,
  ObjectStorage,
  SaveProposalInput,
} from '../ports.js'
import {
  RowMappingError,
  readFils,
  readMilestoneTimes,
  toEvidenceSummary,
  type DisputeRow,
  type EvidenceRow,
  type TransactionEventRow,
  type TransactionRow,
} from './rows.js'

export const EVIDENCE_BUCKET = 'evidence'

/** Turns a PostgREST error into something with the query in it. */
function fail(operation: string, error: { message: string; code?: string }): never {
  throw new Error(`${operation} failed: ${error.message}${error.code ? ` (${error.code})` : ''}`)
}

/* ------------------------------------------------------------------ *
 * Storage
 * ------------------------------------------------------------------ */

export class SupabaseObjectStorage implements ObjectStorage {
  constructor(private readonly client: SupabaseClient) {}

  async put(path: string, bytes: Uint8Array, contentType: string): Promise<void> {
    const { error } = await this.client.storage.from(EVIDENCE_BUCKET).upload(path, bytes, {
      contentType,
      // Never overwrite. Evidence rows are append-only, so an object being
      // replaced would leave a recorded digest describing a file that is gone.
      upsert: false,
    })
    if (error) fail(`storage upload to ${path}`, error)
  }

  async remove(path: string): Promise<void> {
    const { error } = await this.client.storage.from(EVIDENCE_BUCKET).remove([path])
    if (error) fail(`storage remove of ${path}`, error)
  }
}

/* ------------------------------------------------------------------ *
 * Evidence
 * ------------------------------------------------------------------ */

export class SupabaseEvidenceRepository implements EvidenceRepository {
  constructor(private readonly client: SupabaseClient) {}

  async transactionAcceptsEvidence(transactionId: string): Promise<boolean> {
    const { data, error } = await this.client
      .from('transactions')
      .select('state')
      .eq('id', transactionId)
      .maybeSingle<{ state: string }>()

    if (error) fail('reading transaction state', error)
    if (data === null) return false

    // The same set the database uses in app.transaction_accepts_evidence.
    return ['draft', 'pending_acceptance', 'active', 'delivered', 'disputed'].includes(data.state)
  }

  async roleOnTransaction(transactionId: string, userId: string): Promise<Role | null> {
    const { data, error } = await this.client
      .from('transactions')
      .select('buyer_id, seller_id')
      .eq('id', transactionId)
      .maybeSingle<{ buyer_id: string; seller_id: string }>()

    if (error) fail('reading transaction parties', error)
    if (data === null) return null
    if (data.buyer_id === userId) return 'buyer'
    if (data.seller_id === userId) return 'seller'
    return null
  }

  async digestAlreadyFiled(transactionId: string, sha256: string): Promise<boolean> {
    const { count, error } = await this.client
      .from('evidence')
      .select('id', { count: 'exact', head: true })
      .eq('transaction_id', transactionId)
      .eq('sha256', sha256)

    if (error) fail('checking for a duplicate digest', error)
    return (count ?? 0) > 0
  }

  async insert(row: NewEvidenceRow): Promise<EvidenceId> {
    const { data, error } = await this.client
      .from('evidence')
      .insert({
        transaction_id: row.transactionId,
        uploaded_by: row.uploadedBy,
        uploaded_by_role: row.uploadedByRole,
        storage_path: row.storagePath,
        filename: row.filename,
        content_type: row.contentType,
        byte_size: row.byteSize,
        sha256: row.sha256,
        note: row.note,
        extracted_text: row.extractedText,
        extraction_status: row.extractionStatus,
      })
      .select('id')
      .single<{ id: string }>()

    if (error) fail('inserting evidence', error)
    return data.id as EvidenceId
  }
}

/* ------------------------------------------------------------------ *
 * Disputes
 * ------------------------------------------------------------------ */

export class SupabaseDisputeRepository implements DisputeRepository {
  constructor(private readonly client: SupabaseClient) {}

  async loadCase(disputeId: string): Promise<DisputeCase | null> {
    const { data: dispute, error: disputeError } = await this.client
      .from('disputes')
      .select('id, transaction_id, state, opened_by, opened_by_role, buyer_claim, seller_claim, disputed_amount_fils, opened_at')
      .eq('id', disputeId)
      .maybeSingle<DisputeRow>()

    if (disputeError) fail('loading the dispute', disputeError)
    if (dispute === null) return null

    const { data: transaction, error: txnError } = await this.client
      .from('transactions')
      .select('id, state, buyer_id, seller_id, description, terms, total_amount_fils, created_by, acceptance_deadline, created_at, state_changed_at')
      .eq('id', dispute.transaction_id)
      .maybeSingle<TransactionRow>()

    if (txnError) fail('loading the contract', txnError)
    if (transaction === null) {
      throw new RowMappingError(`dispute ${disputeId} points at a contract that does not exist`)
    }

    const { data: evidence, error: evidenceError } = await this.client
      .from('evidence')
      .select('id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256, note, uploaded_at, extracted_text, extraction_status')
      .eq('transaction_id', dispute.transaction_id)
      .order('uploaded_at', { ascending: true })
      .returns<EvidenceRow[]>()

    if (evidenceError) fail('loading the evidence', evidenceError)

    const { data: events, error: eventsError } = await this.client
      .from('transaction_events')
      .select('event, to_state, occurred_at')
      .eq('transaction_id', dispute.transaction_id)
      .order('occurred_at', { ascending: true })
      .returns<TransactionEventRow[]>()

    if (eventsError) fail('loading the contract history', eventsError)

    const times = readMilestoneTimes(events ?? [])

    return {
      disputeId: dispute.id,
      transactionId: dispute.transaction_id,
      description: transaction.description,
      terms: transaction.terms,
      disputedAmount: readFils(dispute.disputed_amount_fils, 'disputes.disputed_amount_fils'),
      // A dispute always has the claim that opened it; the other side may not
      // have answered yet, and an empty string is not an answer.
      buyerClaim: dispute.buyer_claim ?? '',
      sellerClaim:
        dispute.seller_claim === null || dispute.seller_claim.trim().length === 0
          ? null
          : dispute.seller_claim,
      evidence: (evidence ?? []).map(toEvidenceSummary),
      contractAcceptedAt: times.acceptedAt,
      deliveredAt: times.deliveredAt,
      disputeOpenedAt: dispute.opened_at,
    }
  }

  async disputedAmount(disputeId: string): Promise<Fils | null> {
    const { data, error } = await this.client
      .from('disputes')
      .select('disputed_amount_fils')
      .eq('id', disputeId)
      .maybeSingle<{ disputed_amount_fils: number | string }>()

    if (error) fail('reading the disputed amount', error)
    if (data === null) return null
    return readFils(data.disputed_amount_fils, 'disputes.disputed_amount_fils')
  }

  async beginAnalysis(disputeId: string): Promise<void> {
    const { error } = await this.client.rpc('apply_dispute_event', {
      p_dispute_id: disputeId,
      p_event: 'submit_for_ai',
    })
    if (error) fail(`moving dispute ${disputeId} into review`, error)
  }

  async saveProposal(input: SaveProposalInput): Promise<{ proposalId: string }> {
    const { proposal, disputeId, aiCallId } = input

    // One call, because the write has to be one transaction.
    //
    // A finding must cite evidence, and the schema enforces that with a
    // DEFERRABLE INITIALLY DEFERRED trigger that runs at commit. Inserting the
    // proposal, the findings and the citations as separate PostgREST requests
    // puts each one in its own transaction, so the check ran before any
    // citation existed and refused every proposal, leaving the proposal row
    // behind. PostgREST cannot span a transaction across requests, so the
    // whole write lives in `issue_ai_proposal` instead. See migration 0009.
    const { data, error } = await this.client.rpc('issue_ai_proposal', {
      p_dispute_id: disputeId,
      p_decision: proposal.decision,
      p_summary: proposal.summary,
      // Sent explicitly rather than left to the database to infer: the CHECK
      // that the allocation balances is what catches a mismatch, and it can
      // only fire if all three numbers arrive together.
      p_disputed_amount_fils: proposal.allocation.seller + proposal.allocation.buyer,
      p_seller_amount_fils: proposal.allocation.seller,
      p_buyer_amount_fils: proposal.allocation.buyer,
      p_confidence: proposal.confidence,
      p_model_id: proposal.modelId,
      p_issued_at: proposal.issuedAt,
      p_findings: proposal.findings.map((finding) => ({
        statement: finding.statement,
        evidenceIds: finding.evidenceIds,
        citesTerms: finding.citesTerms,
      })),
      // The audit row written moments ago, before the model output was trusted
      // enough to store. Without it there is no way back from a proposal to the
      // prompt, the raw response and the confidence that produced it.
      p_ai_call_id: aiCallId,
    })

    if (error) fail('storing the proposal', error)
    if (typeof data !== 'string' || data.length === 0) {
      throw new RowMappingError('issue_ai_proposal returned no proposal id')
    }

    return { proposalId: data }
  }

  async markEscalated(disputeId: string, reason: string): Promise<void> {
    // The state change goes through the function, not a direct update: the
    // guard trigger refuses anything else.
    const { error } = await this.client.rpc('apply_dispute_event', {
      p_dispute_id: disputeId,
      p_event: 'escalate',
    })
    if (error) fail(`escalating dispute ${disputeId} (${reason})`, error)
  }

  async appendAuditRecord(record: AuditRecord): Promise<{ callId: number }> {
    const { data, error } = await this.client.from('ai_call_log').insert({
      dispute_id: record.disputeId,
      model_id: record.modelId,
      prompt_version: record.promptVersion,
      request_payload: record.requestPayload,
      response_payload: record.responsePayload,
      confidence: record.confidence,
      validation_outcome: record.validationOutcome,
      escalation_reasons: record.escalationReasons,
      latency_ms: record.latencyMs,
      error_message: record.errorMessage,
    })
      .select('id')
      .single()

    if (error) fail('writing the audit record', error)
    const callId = (data as { id?: unknown } | null)?.id
    if (typeof callId !== 'number') {
      throw new RowMappingError('the audit insert returned no id')
    }
    return { callId }
  }
}
