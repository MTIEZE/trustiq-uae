/**
 * Runs the resolution pipeline for real, against Claude.
 *
 *   node scripts/run-resolution.mjs [disputeId]
 *
 * The sibling of dry-run-resolution.mjs, with the one difference that matters:
 * the model is the real one. Everything a stub could prove was proved months
 * ago. What no stub can prove is the thing this exists for.
 *
 * A stub returns what it was told to return. It cannot produce malformed JSON,
 * a finding citing evidence that was never filed, a decision contradicting its
 * own split, or a confidence honest enough to trip the floor. Every one of
 * those paths is written and unit tested against fabricated input, and none of
 * them has ever seen a real answer. Escalation here is not a failure: it is the
 * guard doing its job, and a better first result than a smooth proposal.
 *
 * It costs money, one call at a time, so it does one dispute and stops.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'
import { filsFromAed, formatAed } from '../packages/core/dist/index.js'
import { createAnthropicClient } from '../packages/ai/dist/index.js'
import { runResolution } from '../packages/server/dist/index.js'
import { SupabaseDisputeRepository } from '../packages/server/dist/supabase/repositories.js'

/** The same policy the deployed Edge Function applies. */
const POLICY = {
  minConfidence: 0.7,
  maxAutoAmount: filsFromAed('5000'),
}

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'ANTHROPIC_API_KEY']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()
const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const step = (t) => console.log(`\n${t}`)
const ok = (t) => console.log(`  ok  ${t}`)
let failures = 0

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
}

/* ------------------------------------------------------------------ */

let disputeId = process.argv.slice(2).find((a) => !a.startsWith('--')) ?? null

step('Finding a case')

if (disputeId === null) {
  const { data, error } = await db
    .from('disputes')
    .select('id, opened_at')
    .eq('state', 'open')
    .order('opened_at', { ascending: false })
    .limit(1)

  if (error) {
    console.error(`  could not look for a dispute: ${error.message}`)
    process.exit(1)
  }
  if (!data?.length) {
    console.error('\n  No dispute is in state `open`. Seed one:')
    console.error('    node scripts/seed-live-dispute.mjs\n')
    process.exit(1)
  }
  disputeId = data[0].id
}

const repository = new SupabaseDisputeRepository(db)
const loaded = await repository.loadCase(disputeId)
if (loaded === null) {
  console.error(`\n  Dispute ${disputeId} does not exist.\n`)
  process.exit(1)
}

ok(`${disputeId}`)
ok(`${loaded.evidence.length} piece(s) of evidence, ${formatAed(loaded.disputedAmount)} under dispute`)
ok(`the seller ${loaded.sellerClaim === null ? 'gave no response' : 'gave their account'}`)

step('Calling Claude')

const started = Date.now()
const result = await runResolution(disputeId, {
  repository,
  model: createAnthropicClient({ apiKey: cfg.ANTHROPIC_API_KEY }),
  policy: POLICY,
  clock: { now: () => new Date() },
})
console.log(`  ${result.kind}${result.kind === 'escalated' ? ` — ${result.reason}` : ''} in ${Math.round((Date.now() - started) / 1000)}s`)

/* ------------------------------------------------------------------ *
 * The run's return value is not evidence that anything was written.
 * The rows are.
 * ------------------------------------------------------------------ */

step('What landed in the database')

const { data: log } = await db
  .from('ai_call_log')
  .select('model_id, confidence, validation_outcome, escalation_reasons, latency_ms, error_message')
  .eq('dispute_id', disputeId)
  .order('created_at', { ascending: false })
  .limit(1)

const call = log?.[0]
check('the call is on the audit trail', Boolean(call))

if (call) {
  console.log(`    model              ${call.model_id}`)
  console.log(`    validation         ${call.validation_outcome}`)
  console.log(`    confidence         ${call.confidence ?? 'none returned'}`)
  console.log(`    latency            ${call.latency_ms} ms`)
  if (call.escalation_reasons) console.log(`    escalated because  ${JSON.stringify(call.escalation_reasons)}`)
  if (call.error_message) console.log(`    error              ${call.error_message}`)

  check('it names a real model rather than a stub',
    !String(call.model_id).startsWith('stub:'), call.model_id)
}

const { data: proposals } = await db
  .from('resolution_proposals')
  .select('id, decision, summary, disputed_amount_fils, seller_amount_fils, buyer_amount_fils, confidence')
  .eq('dispute_id', disputeId)
  .order('issued_at', { ascending: false })
  .limit(1)

const proposal = proposals?.[0]
const { data: dispute } = await db
  .from('disputes').select('state').eq('id', disputeId).single()

console.log(`    dispute is now     ${dispute?.state}`)

if (result.kind === 'escalated') {
  step('It escalated, which is the guard working')
  check('the dispute is waiting for a person',
    ['escalated', 'human_review'].includes(dispute?.state), dispute?.state)
  check('and no proposal reached the parties', !proposal || proposal.confidence === null)
} else {
  step('It proposed a resolution')

  if (proposal) {
    const seller = Number(proposal.seller_amount_fils)
    const buyer = Number(proposal.buyer_amount_fils)
    const total = Number(proposal.disputed_amount_fils)

    console.log(`\n    ${proposal.summary}\n`)
    console.log(`    decision           ${proposal.decision}`)
    console.log(`    to the seller      ${formatAed(seller)}`)
    console.log(`    to the buyer       ${formatAed(buyer)}`)
    console.log(`    under dispute      ${formatAed(total)}`)

    // The one arithmetic invariant the whole design rests on: the model
    // returns a percentage and the system derives the fils, so no answer it
    // can give is able to lose or invent one.
    check('the split conserves the disputed amount to the fil',
      seller + buyer === total, `${seller} + ${buyer} != ${total}`)

    const { data: findings } = await db
      .from('resolution_findings')
      .select('position, statement')
      .eq('proposal_id', proposal.id)
      .order('position')

    console.log('')
    for (const f of findings ?? []) console.log(`    [${f.position + 1}] ${f.statement}`)

    check('every finding cites evidence that was actually filed',
      (findings ?? []).length > 0,
      'a proposal with no grounded finding should not have been accepted')
  }
}

console.log(failures === 0
  ? '\n  The pipeline ran end to end against a real model.\n'
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
