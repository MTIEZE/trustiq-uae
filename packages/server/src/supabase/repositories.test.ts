/**
 * Drift guard between the proposal adapter and the SQL function it calls.
 *
 * `saveProposal` used to write the proposal, then each finding, then each
 * finding's citations, as separate PostgREST requests. Each request is its own
 * transaction, so the deferred grounding trigger fired before any citation
 * existed and refused every proposal, leaving the proposal row orphaned. No
 * unit test could see it: the fakes had no transactions to get wrong, and the
 * SQL suite runs a whole file inside one transaction, which is exactly the
 * condition the adapter could not provide.
 *
 * The write now goes through `public.issue_ai_proposal` in a single call. What
 * these tests can check is the seam that replaced it: that the adapter still
 * makes one call rather than a sequence, and that the argument names it sends
 * are the ones the migration actually declares. A typo there is a runtime
 * failure in production and nothing else would catch it.
 *
 * What they cannot check is whether the database accepts the write. That needs
 * a real Postgres: `npm run test:db`, and `scripts/dry-run-resolution.mjs`
 * against the live project.
 */

import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type { Fils, GroundedFinding, ResolutionProposal } from '@trustiq/core'
import { SupabaseDisputeRepository } from './repositories.js'

/** The parameter names `public.issue_ai_proposal` declares, read from the SQL. */
function declaredParameters(): string[] {
  const url = new URL(
    '../../../../supabase/migrations/0009_issue_ai_proposal.sql',
    import.meta.url,
  )
  const sql = readFileSync(url, 'utf8').replace(/--[^\n]*/g, '')
  const signature = /create\s+or\s+replace\s+function\s+public\.issue_ai_proposal\s*\(([\s\S]*?)\)\s*returns/i
    .exec(sql)?.[1]
  if (signature === undefined) {
    throw new Error('issue_ai_proposal not found in migration 0009')
  }
  return [...signature.matchAll(/(p_[a-z_]+)\s+[a-z]/gi)].map((m) => m[1] as string)
}

interface RecordedCall {
  readonly name: string
  readonly args: Record<string, unknown>
}

/**
 * The smallest client that lets the adapter run.
 *
 * `from` throws rather than returning a builder: a proposal write that reaches
 * a table directly is the regression this file exists to catch, and it should
 * be loud.
 */
function fakeClient(rpcResult: { data: unknown; error: { message: string } | null }) {
  const calls: RecordedCall[] = []
  return {
    calls,
    client: {
      rpc(name: string, args: Record<string, unknown>) {
        calls.push({ name, args })
        return Promise.resolve(rpcResult)
      },
      from(table: string) {
        throw new Error(`the adapter reached for table "${table}" instead of the RPC`)
      },
    } as any,
  }
}

const findings: GroundedFinding[] = [
  { statement: 'The brief specified three concepts.', evidenceIds: ['ev-1'] as never },
  { statement: 'Two were delivered.', evidenceIds: ['ev-1', 'ev-2'] as never },
]

const proposal: ResolutionProposal = {
  decision: 'split',
  summary: 'Part of the work met the brief.',
  findings,
  allocation: { seller: 32500 as Fils, buyer: 17500 as Fils },
  confidence: 0.81,
  modelId: 'claude-opus-5',
  issuedAt: '2026-08-26T10:00:00.000Z',
}

describe('SupabaseDisputeRepository.saveProposal', () => {
  it('writes the whole proposal in a single call', async () => {
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    const result = await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
    })

    expect(calls).toHaveLength(1)
    expect(calls[0]?.name).toBe('issue_ai_proposal')
    expect(result).toEqual({ proposalId: 'prop-1' })
  })

  it('sends exactly the arguments the migration declares', async () => {
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
    })

    const sent = Object.keys(calls[0]?.args ?? {}).sort()
    expect(sent).toEqual(declaredParameters().sort())
  })

  it('sends the allocation and its total together, so the balance CHECK can fire', async () => {
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
    })

    const args = calls[0]?.args ?? {}
    expect(args.p_seller_amount_fils).toBe(32500)
    expect(args.p_buyer_amount_fils).toBe(17500)
    expect(args.p_disputed_amount_fils).toBe(50000)
  })

  it('sends the findings with their citations, in order', async () => {
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
    })

    expect(calls[0]?.args.p_findings).toEqual([
      { statement: 'The brief specified three concepts.', evidenceIds: ['ev-1'] },
      { statement: 'Two were delivered.', evidenceIds: ['ev-1', 'ev-2'] },
    ])
  })

  it('throws when the database refuses the write', async () => {
    const { client } = fakeClient({ data: null, error: { message: 'grounding failed' } })
    await expect(
      new SupabaseDisputeRepository(client).saveProposal({ disputeId: 'dispute-1', proposal }),
    ).rejects.toThrow(/grounding failed/)
  })

  it('throws rather than returning an empty id when the call succeeds but returns nothing', async () => {
    // A caller that trusted this would report a proposal id of `undefined` to
    // the parties and record a run as successful that stored nothing.
    const { client } = fakeClient({ data: null, error: null })
    await expect(
      new SupabaseDisputeRepository(client).saveProposal({ disputeId: 'dispute-1', proposal }),
    ).rejects.toThrow(/no proposal id/)
  })
})
