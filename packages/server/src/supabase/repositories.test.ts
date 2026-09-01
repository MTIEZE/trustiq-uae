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

import { readFileSync, readdirSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type { Fils, GroundedFinding, ResolutionProposal } from '@trustiq/core'
import { SupabaseDisputeRepository } from './repositories.js'

/**
 * The parameter names `public.issue_ai_proposal` declares, read from the SQL.
 *
 * Every migration in order, last definition wins. This used to open 0009 by
 * name, which pinned the check to the function's first version: 0027 changed
 * the signature in a different file, and this test would have gone on
 * comparing against a definition the database no longer has.
 */
function declaredParameters(): string[] {
  const dir = new URL('../../../../supabase/migrations/', import.meta.url)
  const pattern =
    /create\s+(?:or\s+replace\s+)?function\s+public\.issue_ai_proposal\s*\(([\s\S]*?)\)\s*returns/gi

  let signature: string | undefined
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = readFileSync(new URL(file, dir), 'utf8').replace(/--[^\n]*/g, '')
    for (const match of sql.matchAll(pattern)) signature = match[1]
  }
  if (signature === undefined) {
    throw new Error('no migration declares issue_ai_proposal')
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
  { statement: 'The brief specified three concepts.', evidenceIds: [] as never, citesTerms: true },
  { statement: 'Two were delivered.', evidenceIds: ['ev-1', 'ev-2'] as never, citesTerms: false },
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
      aiCallId: 4242,
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
      aiCallId: 4242,
    })

    const sent = Object.keys(calls[0]?.args ?? {}).sort()
    expect(sent).toEqual(declaredParameters().sort())
  })

  it('names the run that produced it', async () => {
    // The gap 0027 closed: the audit row and the proposal both existed and
    // nothing pointed one at the other.
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
      aiCallId: 4242,
    })

    expect(calls[0]?.args.p_ai_call_id).toBe(4242)
  })

  it('sends the allocation and its total together, so the balance CHECK can fire', async () => {
    const { calls, client } = fakeClient({ data: 'prop-1', error: null })
    await new SupabaseDisputeRepository(client).saveProposal({
      disputeId: 'dispute-1',
      proposal,
      aiCallId: 4242,
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
      aiCallId: 4242,
    })

    expect(calls[0]?.args.p_findings).toEqual([
      { statement: 'The brief specified three concepts.', evidenceIds: [], citesTerms: true },
      { statement: 'Two were delivered.', evidenceIds: ['ev-1', 'ev-2'], citesTerms: false },
    ])
  })

  it('throws when the database refuses the write', async () => {
    const { client } = fakeClient({ data: null, error: { message: 'grounding failed' } })
    await expect(
      new SupabaseDisputeRepository(client).saveProposal({ disputeId: 'dispute-1', proposal, aiCallId: 4242 }),
    ).rejects.toThrow(/grounding failed/)
  })

  it('throws rather than returning an empty id when the call succeeds but returns nothing', async () => {
    // A caller that trusted this would report a proposal id of `undefined` to
    // the parties and record a run as successful that stored nothing.
    const { client } = fakeClient({ data: null, error: null })
    await expect(
      new SupabaseDisputeRepository(client).saveProposal({ disputeId: 'dispute-1', proposal, aiCallId: 4242 }),
    ).rejects.toThrow(/no proposal id/)
  })
})
