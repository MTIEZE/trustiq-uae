/**
 * The seams between server logic and the outside world.
 *
 * Everything the server does is written against these interfaces, so the whole
 * of it runs in tests against in-memory fakes: no Supabase, no network, no
 * API key. The Supabase-backed implementations are thin adapters over these.
 */

import type { EvidenceId, Fils, ResolutionProposal, Role } from '@trustiq/core'
import type { AuditRecord, DisputeCase } from '@trustiq/ai'
import type { ExtractionStatus } from './text-extraction.js'

export interface NewEvidenceRow {
  readonly transactionId: string
  readonly uploadedBy: string
  readonly uploadedByRole: Role
  readonly storagePath: string
  readonly filename: string
  readonly contentType: string
  readonly byteSize: number
  /** Always the digest the server computed. Never a value a client sent. */
  readonly sha256: string
  readonly note: string | null
  /**
   * Readable content, taken from the same bytes the digest covers. Null when
   * there is none, and `extractionStatus` says which kind of none.
   */
  readonly extractedText: string | null
  readonly extractionStatus: ExtractionStatus
}

export interface ObjectStorage {
  /** Writes bytes. Must reject rather than overwrite if the path is taken. */
  put(path: string, bytes: Uint8Array, contentType: string): Promise<void>
  /** Used to clean up an object whose row failed to insert. */
  remove(path: string): Promise<void>
}

export interface EvidenceRepository {
  /** State check: a closed contract accepts no new evidence. */
  transactionAcceptsEvidence(transactionId: string): Promise<boolean>
  /** The party's role on the contract, or null if they are not on it. */
  roleOnTransaction(transactionId: string, userId: string): Promise<Role | null>
  /** Whether this exact digest is already filed on this contract. */
  digestAlreadyFiled(transactionId: string, sha256: string): Promise<boolean>
  insert(row: NewEvidenceRow): Promise<EvidenceId>
}

export interface DisputeRepository {
  /** Assembles the case file the model reasons over. Null if no such dispute. */
  loadCase(disputeId: string): Promise<DisputeCase | null>
  /** The amount under dispute, used to reject a case that changed mid-flight. */
  disputedAmount(disputeId: string): Promise<Fils | null>
  /**
   * Moves the dispute from `open` to `ai_review`.
   *
   * Fired before the model is called, because the later transitions are only
   * legal from `ai_review`: without it, the first escalation is refused by the
   * state machine.
   */
  beginAnalysis(disputeId: string): Promise<void>

  /** Stores the proposal and moves the dispute to `proposal_issued`. */
  saveProposal(input: SaveProposalInput): Promise<{ proposalId: string }>
  markEscalated(disputeId: string, reason: string): Promise<void>

  /**
   * Writes the audit row and hands back its id.
   *
   * The id is what a proposal is later stamped with, which is the only way the
   * two can be tied together: the audit row is written first, on purpose, so a
   * run is recorded even when the store afterwards fails, and the log is
   * append-only so it can never be told about the proposal in arrears.
   */
  appendAuditRecord(record: AuditRecord): Promise<{ callId: number }>
}

export interface SaveProposalInput {
  readonly disputeId: string
  readonly proposal: ResolutionProposal
  /** The run this proposal came out of, from `appendAuditRecord`. */
  readonly aiCallId: number
}

export interface Clock {
  now(): Date
}
