/**
 * @trustiq/server
 *
 * Server-side flows: the evidence upload path (the only writer of evidence
 * rows, and the only place a digest is computed) and the dispute resolution
 * run that drives @trustiq/ai and records what it did.
 *
 * Everything here is written against the ports in ./ports, so it runs in tests
 * against in-memory fakes.
 */

export {
  ALLOWED_CONTENT_TYPES,
  MAX_EVIDENCE_BYTES,
  sha256Hex,
  uploadEvidence,
  type UploadDeps,
  type UploadEvidenceInput,
  type UploadRejection,
  type UploadRejectionCode,
  type UploadedEvidence,
} from './evidence.js'

export { describeCause, runResolution, type RunDeps, type RunResult } from './resolution-run.js'

export type {
  Clock,
  DisputeRepository,
  EvidenceRepository,
  NewEvidenceRow,
  ObjectStorage,
  SaveProposalInput,
} from './ports.js'

export {
  EVIDENCE_BUCKET,
  SupabaseDisputeRepository,
  SupabaseEvidenceRepository,
  SupabaseObjectStorage,
} from './supabase/repositories.js'

export {
  createServiceRoleClient,
  createUserClient,
  readConnectionFromEnv,
  type SupabaseConnection,
} from './supabase/client.js'

export {
  RowMappingError,
  readFils,
  readMilestoneTimes,
  readRole,
  toEvidenceSummary,
  type DisputeRow,
  type EvidenceRow,
  type TransactionEventRow,
  type TransactionRow,
} from './supabase/rows.js'
