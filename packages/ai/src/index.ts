/**
 * @trustiq/ai
 *
 * The dispute resolution pipeline: builds the case file, calls the model,
 * validates what comes back against @trustiq/core, and either produces a
 * proposal the parties may see or an escalation to a human. Every run,
 * including every failure, produces an audit record.
 */

export { PROMPT_VERSION, SYSTEM_PROMPT, buildUserContent } from './prompt.js'
export { RESOLUTION_SCHEMA, type RawResolution } from './schema.js'
export { resolveDispute } from './resolve.js'
export { DEFAULT_MODEL, createAnthropicClient, type AnthropicClientOptions } from './anthropic-client.js'
export type {
  AuditRecord,
  DisputeCase,
  EscalationCause,
  EvidenceSummary,
  ModelClient,
  ModelOutcome,
  ModelRequest,
  ResolutionOutcome,
  ResolveOptions,
} from './types.js'
