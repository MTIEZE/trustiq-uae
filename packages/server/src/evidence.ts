/**
 * The evidence upload path.
 *
 * This is the only way an evidence row is created: migration 0007 removed the
 * client INSERT policy, so nothing else can write one. That matters because of
 * the single rule this file exists to enforce:
 *
 *   The digest is computed here, from the bytes the server is about to store.
 *   A value the client sends is never written to the column.
 *
 * A hash the uploader chose proves nothing. Every later guarantee in the
 * product, including every finding the model grounds in a document, rests on
 * this one being true.
 */

import { createHash } from 'node:crypto'
import { err, ok, type EvidenceId, type Result, type Role } from '@trustiq/core'
import type { Clock, EvidenceRepository, ObjectStorage } from './ports.js'

export const MAX_EVIDENCE_BYTES = 52_428_800 // 50 MiB, matching the DB check

/** Kept in step with the bucket's allowed_mime_types in migration 0007. */
export const ALLOWED_CONTENT_TYPES: readonly string[] = [
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/webp',
  'text/plain',
  'text/markdown',
  'text/csv',
  'application/zip',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
]

export interface UploadEvidenceInput {
  readonly transactionId: string
  readonly userId: string
  readonly filename: string
  readonly contentType: string
  readonly bytes: Uint8Array
  readonly note: string | null
  /**
   * Optional digest the client claims for what it uploaded.
   *
   * Used only to detect a corrupted transfer. It is compared against the
   * server's own digest and then discarded; it never reaches the database.
   */
  readonly clientClaimedSha256?: string
}

export type UploadRejectionCode =
  | 'EMPTY_FILE'
  | 'FILE_TOO_LARGE'
  | 'UNSUPPORTED_CONTENT_TYPE'
  | 'INVALID_FILENAME'
  | 'NOT_A_PARTY'
  | 'TRANSACTION_CLOSED'
  | 'DUPLICATE_EVIDENCE'
  | 'DIGEST_MISMATCH'
  | 'STORAGE_FAILED'
  | 'RECORD_FAILED'

export interface UploadRejection {
  readonly code: UploadRejectionCode
  readonly message: string
}

export interface UploadedEvidence {
  readonly evidenceId: EvidenceId
  readonly storagePath: string
  readonly sha256: string
  readonly byteSize: number
  readonly role: Role
}

export interface UploadDeps {
  readonly storage: ObjectStorage
  readonly repository: EvidenceRepository
  readonly clock: Clock
  /** Injected so the storage path is deterministic in tests. */
  readonly newId: () => string
}

export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex')
}

export async function uploadEvidence(
  input: UploadEvidenceInput,
  deps: UploadDeps,
): Promise<Result<UploadedEvidence, UploadRejection>> {
  const shapeError = checkShape(input)
  if (shapeError !== null) return err(shapeError)

  const role = await deps.repository.roleOnTransaction(input.transactionId, input.userId)
  if (role === null) {
    return err({
      code: 'NOT_A_PARTY',
      message: 'Only the buyer or the seller on a contract can file evidence against it.',
    })
  }

  if (!(await deps.repository.transactionAcceptsEvidence(input.transactionId))) {
    return err({
      code: 'TRANSACTION_CLOSED',
      message: 'This contract has closed and no longer accepts evidence.',
    })
  }

  // The digest, computed here, from these bytes. Everything downstream trusts
  // this value, so nothing upstream is allowed to supply it.
  const sha256 = sha256Hex(input.bytes)

  if (input.clientClaimedSha256 !== undefined && input.clientClaimedSha256.toLowerCase() !== sha256) {
    // Not a security check: a client that wanted to lie would simply omit the
    // field. It catches a transfer that arrived corrupted, which is worth
    // failing loudly rather than filing a document nobody can reproduce.
    return err({
      code: 'DIGEST_MISMATCH',
      message: 'The uploaded bytes do not match the digest the client reported. The transfer was corrupted; try again.',
    })
  }

  if (await deps.repository.digestAlreadyFiled(input.transactionId, sha256)) {
    return err({
      code: 'DUPLICATE_EVIDENCE',
      message: 'This exact file has already been filed on this contract.',
    })
  }

  const storagePath = `${input.transactionId}/${deps.clock.now().toISOString()}-${deps.newId()}`

  try {
    await deps.storage.put(storagePath, input.bytes, input.contentType)
  } catch (error) {
    return err({ code: 'STORAGE_FAILED', message: describe(error) })
  }

  try {
    const evidenceId = await deps.repository.insert({
      transactionId: input.transactionId,
      uploadedBy: input.userId,
      uploadedByRole: role,
      storagePath,
      filename: input.filename,
      contentType: input.contentType,
      byteSize: input.bytes.byteLength,
      sha256,
      note: input.note,
    })
    return ok({ evidenceId, storagePath, sha256, byteSize: input.bytes.byteLength, role })
  } catch (error) {
    // The object is written but has no row, so nothing can reference it.
    // Remove it rather than leaving an unreachable file in the bucket. If the
    // cleanup itself fails there is nothing more to do here: the orphan is
    // inert, and the upload still has to be reported as failed.
    await deps.storage.remove(storagePath).catch(() => undefined)
    return err({ code: 'RECORD_FAILED', message: describe(error) })
  }
}

function checkShape(input: UploadEvidenceInput): UploadRejection | null {
  if (input.bytes.byteLength === 0) {
    return { code: 'EMPTY_FILE', message: 'The file is empty.' }
  }
  if (input.bytes.byteLength > MAX_EVIDENCE_BYTES) {
    return {
      code: 'FILE_TOO_LARGE',
      message: `The file is ${input.bytes.byteLength} bytes; the limit is ${MAX_EVIDENCE_BYTES}.`,
    }
  }
  if (!ALLOWED_CONTENT_TYPES.includes(input.contentType)) {
    return {
      code: 'UNSUPPORTED_CONTENT_TYPE',
      message: `${input.contentType} cannot be filed as evidence.`,
    }
  }
  const filename = input.filename.trim()
  if (filename.length === 0 || filename.length > 255) {
    return { code: 'INVALID_FILENAME', message: 'The filename is missing or too long.' }
  }
  // The filename is metadata shown to the other party, never a path. Reject
  // separators anyway so it cannot be mistaken for one downstream.
  if (filename.includes('/') || filename.includes('\\') || filename.includes('\0')) {
    return { code: 'INVALID_FILENAME', message: 'The filename contains path separators.' }
  }
  return null
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
