/**
 * Runs the resolution pipeline against the live project with a stub model.
 *
 *   node scripts/dry-run-resolution.mjs [disputeId] [--refuse|--invent-evidence|--unsure]
 *
 * Everything here is the real thing except the model call: the real
 * `runResolution`, the real Supabase adapters, the real schema, the real
 * validation. Only `ModelClient` is replaced, by a stub that returns a
 * pre-written answer instead of spending money on an API call.
 *
 * That makes this the test for the parts a unit test cannot reach: whether the
 * live database accepts the writes, whether the dispute state machine allows
 * the transitions in the order the pipeline fires them, and whether an audit
 * row lands. Whether the model's *judgment* is any good is a separate question
 * and this script says nothing about it.
 *
 * The stub identifies itself as `stub:dry-run/<mode>` in `model_id`, so a
 * proposal produced this way is distinguishable from a real one for as long as
 * the row exists. Do not change that to something that looks like a model name.
 *
 * Modes, each exercising a different branch:
 *
 *   (default)          a well-formed answer citing real evidence -> proposal
 *   --refuse           the model's classifiers decline           -> escalation
 *   --invent-evidence  a finding cites an id that does not exist -> escalation
 *   --unsure           confidence below the policy floor         -> escalation
 *
 * A dispute can only be resolved once, so to try a second mode, re-seed first:
 *
 *   node scripts/seed-live-dispute.mjs
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'
import { filsFromAed } from '../packages/core/dist/index.js'
import { runResolution } from '../packages/server/dist/index.js'
import { SupabaseDisputeRepository } from '../packages/server/dist/supabase/repositories.js'

/** The same policy the deployed Edge Function applies. */
const POLICY = {
  minConfidence: 0.7,
  maxAutoAmount: filsFromAed('5000'),
}

/* ------------------------------------------------------------------ */

function env() {
  const raw = readFileSync('.env', 'utf8')
  const out = {}
  for (const line of raw.split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
    if (!out[k]) {
      console.error(`${k} is not set in .env`)
      process.exit(1)
    }
  }
  return out
}

const step = (text) => console.log(`\n${text}`)
const ok = (text) => console.log(`  ok  ${text}`)
const no = (text) => console.log(`  !!  ${text}`)

const MODES = {
  '--refuse': 'refuse',
  '--invent-evidence': 'invent-evidence',
  '--unsure': 'unsure',
}

/* ------------------------------------------------------------------ */

const cfg = env()
const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const args = process.argv.slice(2)
const mode = args.map((a) => MODES[a]).find(Boolean) ?? 'proposal'
let disputeId = args.find((a) => !a.startsWith('--')) ?? null

/**
 * Stands in for the Anthropic client.
 *
 * It reads nothing and reasons about nothing: the answer is written here, in
 * the shape RESOLUTION_SCHEMA describes, so that the code downstream of the
 * model gets exercised with realistic input. `evidenceIds` are passed in from
 * the case that was actually loaded, because a finding citing an id that is not
 * on the case is supposed to be rejected, and only the `invent-evidence` mode
 * should trigger that.
 */
function stubModel(evidenceIds, behaviour) {
  return {
    modelId: `stub:dry-run/${behaviour}`,
    promptVersion: 'stub-1',
    async complete(request) {
      // Proves the prompt was built rather than skipped. If the pipeline ever
      // stops assembling a case file, this fires here instead of silently
      // sending an empty prompt to a real model later.
      if (!request.userContent.includes('amount under dispute:')) {
        return {
          kind: 'error',
          message: 'the user content did not look like a case file',
          retryable: false,
          latencyMs: 0,
        }
      }

      if (behaviour === 'refuse') {
        return { kind: 'refused', category: 'stubbed_refusal', modelId: this.modelId, latencyMs: 3 }
      }

      const cited = behaviour === 'invent-evidence'
        ? ['00000000-0000-4000-8000-000000000000']
        : evidenceIds

      const answer = {
        decision: 'split',
        summary:
          'The brief asked for three distinct concepts and two were delivered as ' +
          'distinct work, with the third a variation rather than a new concept. ' +
          'The delivery was inside the agreed window. The seller is credited for ' +
          'the work that met the brief and the buyer for the part that did not.',
        findings: [
          {
            statement: 'The brief required three distinct concepts within seven days.',
            evidenceIds: cited.slice(0, 1),
          },
          {
            statement: 'Two distinct concepts and one colour variation were delivered on day seven.',
            evidenceIds: cited.slice(0, 2),
          },
        ],
        sellerPercent: 65,
        confidence: behaviour === 'unsure' ? 0.42 : 0.81,
      }

      return { kind: 'completed', json: JSON.stringify(answer), modelId: this.modelId, latencyMs: 7 }
    },
  }
}

/* ------------------------------------------------------------------ */

step('Finding a dispute to run')

if (disputeId === null) {
  const { data, error } = await db
    .from('disputes')
    .select('id, state, opened_at')
    .eq('state', 'open')
    .order('opened_at', { ascending: false })
    .limit(1)

  if (error) {
    console.error(`  could not look for a dispute: ${error.message}`)
    process.exit(1)
  }
  if (!data?.length) {
    console.error('\n  No dispute is in state `open`.')
    console.error('  Seed one with:  node scripts/seed-live-dispute.mjs\n')
    process.exit(1)
  }
  disputeId = data[0].id
  ok(`using the most recent open dispute: ${disputeId}`)
} else {
  ok(`using the dispute given on the command line: ${disputeId}`)
}

const repository = new SupabaseDisputeRepository(db)

const loaded = await repository.loadCase(disputeId)
if (loaded === null) {
  console.error(`\n  Dispute ${disputeId} does not exist.\n`)
  process.exit(1)
}
ok(`case file assembled from the live database: ${loaded.evidence.length} piece(s) of evidence, ${loaded.disputedAmount} fils under dispute`)

step(`Running the pipeline in "${mode}" mode, with a stub in place of the model`)

const before = new Date().toISOString()
const result = await runResolution(disputeId, {
  repository,
  model: stubModel(loaded.evidence.map((e) => e.id), mode),
  policy: POLICY,
  clock: { now: () => new Date() },
})

console.log(`  result: ${result.kind}${result.kind === 'escalated' ? ` — ${result.reason}` : ''}`)

/* ------------------------------------------------------------------ *
 * Read it all back. The run's own return value is not evidence that
 * anything was written; the rows are.
 * ------------------------------------------------------------------ */

step('Reading the live rows back')

let failures = 0
const check = (condition, text) => {
  if (condition) ok(text)
  else {
    no(text)
    failures += 1
  }
}

const { data: dispute } = await db
  .from('disputes')
  .select('state, state_changed_at')
  .eq('id', disputeId)
  .single()

console.log(`  dispute state is now: ${dispute?.state}`)

const { data: log } = await db
  .from('ai_call_log')
  .select('model_id, prompt_version, validation_outcome, confidence, escalation_reasons, latency_ms, error_message, created_at')
  .eq('dispute_id', disputeId)
  .gte('created_at', before)
  .order('created_at', { ascending: false })

check((log?.length ?? 0) > 0, 'an audit row was written for this run')
if (log?.length) {
  const row = log[0]
  console.log(`      model_id           ${row.model_id}`)
  console.log(`      validation_outcome ${row.validation_outcome}`)
  console.log(`      confidence         ${row.confidence}`)
  console.log(`      escalation_reasons ${JSON.stringify(row.escalation_reasons)}`)
  if (row.error_message) console.log(`      error_message      ${row.error_message}`)
}

const { data: proposals } = await db
  .from('resolution_proposals')
  .select('id, decision, seller_amount_fils, buyer_amount_fils, disputed_amount_fils, confidence, model_id')
  .eq('dispute_id', disputeId)

if (mode === 'proposal') {
  check(result.kind === 'proposal', 'the run produced a proposal')
  check(dispute?.state === 'proposal_issued', 'the dispute moved to proposal_issued')
  check((proposals?.length ?? 0) === 1, 'exactly one proposal row exists')

  const p = proposals?.[0]
  if (p) {
    const total = Number(p.seller_amount_fils) + Number(p.buyer_amount_fils)
    console.log(`      decision  ${p.decision}`)
    console.log(`      seller    ${p.seller_amount_fils} fils`)
    console.log(`      buyer     ${p.buyer_amount_fils} fils`)
    console.log(`      model_id  ${p.model_id}`)
    check(total === Number(loaded.disputedAmount), `the split conserves the total: ${p.seller_amount_fils} + ${p.buyer_amount_fils} = ${total}`)
    check(String(p.model_id).startsWith('stub:'), 'the row says plainly that no real model was involved')

    const { data: findings } = await db
      .from('resolution_findings')
      .select('id, position, statement')
      .eq('proposal_id', p.id)
      .order('position')

    check((findings?.length ?? 0) === 2, `both findings were stored (${findings?.length ?? 0})`)

    const { data: citations } = await db
      .from('resolution_finding_evidence')
      .select('finding_id, evidence_id')
      .in('finding_id', (findings ?? []).map((f) => f.id))

    // The stub cites the first evidence item in one finding and the first two
    // in the other, so how many citations to expect depends on the case.
    const n = loaded.evidence.length
    const expected = Math.min(1, n) + Math.min(2, n)
    check(
      (citations?.length ?? 0) === expected,
      `every citation was stored (${citations?.length ?? 0} of ${expected})`,
    )

    const known = new Set(loaded.evidence.map((e) => e.id))
    check(
      (citations ?? []).every((c) => known.has(c.evidence_id)),
      'every stored citation points at evidence that is really on the case',
    )
  }
} else {
  check(result.kind === 'escalated', 'the run escalated instead of issuing a proposal')
  check(dispute?.state === 'escalated', 'the dispute moved to escalated')
  check((proposals?.length ?? 0) === 0, 'no proposal was stored')
  check(
    (log?.[0]?.validation_outcome ?? '') !== 'accepted',
    `the audit row records why: ${log?.[0]?.validation_outcome}`,
  )
}

step(failures === 0 ? 'All checks passed.' : `${failures} check(s) failed.`)
console.log(
  failures === 0
    ? '\n  The pipeline works against the live project. The model call is the only\n' +
      '  part still stubbed; everything around it has now run for real.\n'
    : '',
)
process.exit(failures === 0 ? 0 : 1)
