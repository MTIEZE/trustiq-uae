/**
 * The one impure edge of the pipeline: the actual Anthropic call.
 *
 * Everything else in this package is pure and tested with a fake client. This
 * file exists to turn SDK specifics into the small ModelOutcome union, so the
 * pipeline never has to know about content blocks or SDK error classes.
 */

import Anthropic from '@anthropic-ai/sdk'
import { PROMPT_VERSION } from './prompt.js'
import type { ModelClient, ModelOutcome, ModelRequest } from './types.js'

export const DEFAULT_MODEL = 'claude-opus-5'

export interface AnthropicClientOptions {
  readonly apiKey?: string
  readonly model?: string
  readonly maxTokens?: number
  /** Thinking depth. 'high' is the default; raise for hard cases, lower for cost. */
  readonly effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max'
}

export function createAnthropicClient(options: AnthropicClientOptions = {}): ModelClient {
  const model = options.model ?? DEFAULT_MODEL
  const maxTokens = options.maxTokens ?? 16000
  const effort = options.effort ?? 'high'

  // Omitting apiKey lets the SDK resolve credentials from the environment,
  // which is what a server deployment should do. Never take a key from a client.
  const sdk = options.apiKey === undefined ? new Anthropic() : new Anthropic({ apiKey: options.apiKey })

  return {
    modelId: model,
    promptVersion: PROMPT_VERSION,

    async complete(request: ModelRequest): Promise<ModelOutcome> {
      const startedAt = Date.now()
      const elapsed = (): number => Date.now() - startedAt

      try {
        const response = await sdk.messages.create({
          model,
          max_tokens: maxTokens,
          system: request.system,
          messages: [{ role: 'user', content: request.userContent }],
          output_config: {
            effort,
            format: { type: 'json_schema', schema: request.schema },
          },
        })

        // Check the stop reason before touching content. On a refusal the
        // content array is empty or partial, and indexing it blindly is the
        // classic way this breaks in production.
        if (response.stop_reason === 'refusal') {
          return {
            kind: 'refused',
            category: response.stop_details?.category ?? null,
            modelId: response.model,
            latencyMs: elapsed(),
          }
        }

        if (response.stop_reason === 'max_tokens') {
          return { kind: 'truncated', modelId: response.model, latencyMs: elapsed() }
        }

        const json = response.content
          .filter((block): block is Anthropic.TextBlock => block.type === 'text')
          .map((block) => block.text)
          .join('')

        if (json.trim().length === 0) {
          return {
            kind: 'error',
            message: `model returned no text content (stop_reason: ${String(response.stop_reason)})`,
            retryable: true,
            latencyMs: elapsed(),
          }
        }

        return { kind: 'completed', json, modelId: response.model, latencyMs: elapsed() }
      } catch (error) {
        return { kind: 'error', ...classify(error), latencyMs: elapsed() }
      }
    },
  }
}

/**
 * Retryable means "the same request might succeed later": rate limits,
 * overload, transport failures. A 400 will fail again identically, so retrying
 * it just delays the escalation the case already needs.
 */
function classify(error: unknown): { message: string; retryable: boolean } {
  if (error instanceof Anthropic.RateLimitError) {
    return { message: `rate limited: ${error.message}`, retryable: true }
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return { message: `connection failed: ${error.message}`, retryable: true }
  }
  if (error instanceof Anthropic.InternalServerError) {
    return { message: `upstream error: ${error.message}`, retryable: true }
  }
  if (error instanceof Anthropic.APIError) {
    return { message: `api error ${String(error.status)}: ${error.message}`, retryable: false }
  }
  return { message: error instanceof Error ? error.message : String(error), retryable: false }
}
