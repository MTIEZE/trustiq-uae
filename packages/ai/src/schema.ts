/**
 * The JSON Schema the model's response is constrained to.
 *
 * Note what is NOT here: fils amounts. The model returns a whole percentage to
 * the seller and the pipeline computes the split with allocate(), so the model
 * cannot lose or invent a fil no matter how its arithmetic goes. Judgment is
 * the model's job; money arithmetic is the code's.
 *
 * Structured outputs do not enforce numeric ranges, so `sellerPercent` being
 * 0-100 is checked after parsing, not here.
 */

export const RESOLUTION_SCHEMA: Record<string, unknown> = {
  type: 'object',
  additionalProperties: false,
  required: ['decision', 'summary', 'findings', 'sellerPercent', 'confidence'],
  properties: {
    decision: {
      type: 'string',
      enum: ['release_to_seller', 'refund_to_buyer', 'split'],
      description:
        'The shape of the outcome. Must agree with sellerPercent: 100 is release_to_seller, 0 is refund_to_buyer, anything between is split.',
    },
    summary: {
      type: 'string',
      description:
        'Two to four sentences explaining the outcome to both parties in plain language. Address what each side claimed.',
    },
    findings: {
      type: 'array',
      description:
        'The factual basis for the outcome. Every statement must rest on submitted evidence, on the agreed terms, or on both.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['statement', 'evidenceIds', 'citesTerms'],
        properties: {
          statement: {
            type: 'string',
            description: 'One factual claim, stated plainly.',
          },
          evidenceIds: {
            type: 'array',
            description:
              'Ids of the evidence supporting this statement. Every id must appear in the case file. Never invent one. Leave empty when the statement rests on the agreed terms alone.',
            items: { type: 'string' },
          },
          citesTerms: {
            type: 'boolean',
            description:
              'True when this statement is founded on the agreed terms: what was promised, by when, and on what conditions. Use it rather than leaving a statement about the agreement unsupported. A statement with no evidence ids and citesTerms false is refused.',
          },
        },
      },
    },
    sellerPercent: {
      type: 'integer',
      description:
        'Whole percentage of the disputed amount that should go to the seller, 0 to 100. The remainder goes to the buyer. Do not compute currency amounts.',
    },
    confidence: {
      type: 'number',
      description:
        'How confident you are in this outcome, 0 to 1. Report what the evidence supports; a low number on a thin case is the correct answer, and cases below the threshold go to a human reviewer.',
    },
  },
}

/** The shape RESOLUTION_SCHEMA produces, before validation. */
export interface RawResolution {
  decision: string
  summary: string
  findings: { statement: string; evidenceIds: string[]; citesTerms: boolean }[]
  sellerPercent: number
  confidence: number
}
