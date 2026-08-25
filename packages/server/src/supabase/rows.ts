/**
 * Turning database rows into domain values.
 *
 * Kept apart from the queries on purpose: this half is pure and tested, and it
 * is where the mistakes actually live. A wrong column name fails loudly the
 * first time anything runs; a silently mis-parsed amount does not.
 */

import { fils, type EvidenceId, type Fils, type Role } from '@trustiq/core'
import type { EvidenceSummary } from '@trustiq/ai'

/* ------------------------------------------------------------------ *
 * Row shapes, as PostgREST returns them
 * ------------------------------------------------------------------ */

export interface EvidenceRow {
  id: string
  transaction_id: string
  uploaded_by: string
  uploaded_by_role: string
  storage_path: string
  filename: string
  content_type: string
  byte_size: number
  sha256: string
  note: string | null
  uploaded_at: string
}

export interface TransactionRow {
  id: string
  state: string
  buyer_id: string
  seller_id: string
  description: string
  terms: string
  total_amount_fils: number | string
  created_by: string
  acceptance_deadline: string | null
  created_at: string
  state_changed_at: string
}

export interface DisputeRow {
  id: string
  transaction_id: string
  state: string
  opened_by: string
  opened_by_role: string
  buyer_claim: string | null
  seller_claim: string | null
  disputed_amount_fils: number | string
  opened_at: string
}

export interface TransactionEventRow {
  event: string
  to_state: string
  occurred_at: string
}

export class RowMappingError extends Error {
  override readonly name = 'RowMappingError'
}

/* ------------------------------------------------------------------ *
 * Amounts
 * ------------------------------------------------------------------ */

/**
 * Reads a fils column.
 *
 * PostgREST serialises `bigint` as a JSON number when it fits and as a string
 * otherwise, and which one you get depends on the value rather than the
 * column. Both are handled, and anything else is refused rather than coerced:
 * `Number(null)` is 0, and a zero that should have been an error is exactly
 * the kind of thing that reaches a ledger.
 */
export function readFils(value: unknown, column: string): Fils {
  if (typeof value === 'number') {
    if (!Number.isInteger(value)) {
      throw new RowMappingError(`${column}: expected a whole number of fils, got ${value}`)
    }
    return fils(value)
  }
  if (typeof value === 'string') {
    if (!/^-?\d+$/.test(value)) {
      throw new RowMappingError(`${column}: "${value}" is not an integer`)
    }
    const parsed = Number(value)
    if (!Number.isSafeInteger(parsed)) {
      throw new RowMappingError(`${column}: "${value}" is outside the safe integer range`)
    }
    return fils(parsed)
  }
  throw new RowMappingError(`${column}: expected a number or a string, got ${typeof value}`)
}

/* ------------------------------------------------------------------ *
 * Enums
 * ------------------------------------------------------------------ */

export function readRole(value: unknown, column: string): Role {
  if (value === 'buyer' || value === 'seller') return value
  throw new RowMappingError(`${column}: "${String(value)}" is not a role`)
}

/* ------------------------------------------------------------------ *
 * Evidence
 * ------------------------------------------------------------------ */

/**
 * Evidence as the model will see it.
 *
 * `extractedText` is null here on purpose. Text extraction happens in the
 * upload path, not at read time, and inventing a value would put something in
 * front of the model that no document actually says.
 */
export function toEvidenceSummary(row: EvidenceRow): EvidenceSummary {
  return {
    id: row.id as EvidenceId,
    uploadedByRole: readRole(row.uploaded_by_role, 'evidence.uploaded_by_role'),
    filename: row.filename,
    contentType: row.content_type,
    uploadedAt: row.uploaded_at,
    sha256: row.sha256,
    note: row.note,
    extractedText: null,
  }
}

/* ------------------------------------------------------------------ *
 * Timestamps from the audit log
 * ------------------------------------------------------------------ */

/**
 * When a contract was accepted and when delivery was declared.
 *
 * Taken from the append-only event log rather than from columns on the
 * contract, because the log is the record that cannot be rewritten. A contract
 * can be delivered, sent back for revision and delivered again; the latest
 * delivery is the one the dispute is about.
 */
export function readMilestoneTimes(events: readonly TransactionEventRow[]): {
  acceptedAt: string | null
  deliveredAt: string | null
} {
  let acceptedAt: string | null = null
  let deliveredAt: string | null = null

  for (const event of events) {
    if (event.event === 'accept') {
      // The first acceptance is the one that made the contract binding.
      acceptedAt ??= event.occurred_at
    }
    if (event.event === 'mark_delivered') {
      deliveredAt = event.occurred_at
    }
    if (event.event === 'request_revision') {
      // Sent back, so the previous delivery no longer stands.
      deliveredAt = null
    }
  }

  return { acceptedAt, deliveredAt }
}
