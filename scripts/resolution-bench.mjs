/**
 * Runs the resolution pipeline across a spread of disputes and reports where
 * it lands.
 *
 *   node scripts/resolution-bench.mjs            every case
 *   node scripts/resolution-bench.mjs 3 7        only those cases
 *   node scripts/resolution-bench.mjs --seed     seed them, call nothing
 *
 * Why this exists. On 1 September 2026 the acceptance rate rested on four live
 * calls: one accepted, one below the confidence floor, one citing evidence that
 * did not exist, one escalated by policy. That number is the product's central
 * claim — a resolution in under a minute — and four points cannot tell you
 * whether it holds, which shapes of dispute it holds for, or whether the
 * confidence floor sits in the right place. It is also the first number a
 * payment partner will ask for.
 *
 * The cases below are constructed, and they are constructed to be awkward. A
 * bench of ten clean disputes would report a flattering number that says
 * nothing. Half of these should escalate, and an escalation here is the guard
 * working rather than a failure: the point is to find out whether it works for
 * the right reason.
 *
 * Costs one model call per case. Every run is on the audit trail whatever
 * happens, so the numbers this prints can be recomputed from the database
 * later and do not have to be believed.
 *
 * The accounts are @example.test, which app.real_profiles excludes, so nothing
 * here reaches the operator console's counts.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'
import { filsFromAed, formatAed } from '../packages/core/dist/index.js'
import { createAnthropicClient } from '../packages/ai/dist/index.js'
import { runResolution, uploadEvidence } from '../packages/server/dist/index.js'
import {
  SupabaseDisputeRepository,
  SupabaseEvidenceRepository,
  SupabaseObjectStorage,
} from '../packages/server/dist/supabase/repositories.js'

/** The same policy the deployed Edge Function applies. */
const POLICY = {
  minConfidence: 0.7,
  maxAutoAmount: filsFromAed('5000'),
}

const RUN = `bench-${Math.random().toString(16).slice(2, 8)}`

/* ------------------------------------------------------------------------ *
 * The cases.
 *
 * `expect` is what I think should happen, written down before the run so the
 * comparison afterwards means something. It is a prediction, not an assertion:
 * nothing fails because the model disagreed with me.
 * ------------------------------------------------------------------------ */

const CASES = [
  {
    slug: 'shortfall',
    expect: 'a split; the seller\'s own note admits the gap',
    description: 'Logo design for a startup',
    terms:
      'Deliver 3 distinct logo concepts within 7 days. Two rounds of revision included. ' +
      'Final files supplied as SVG and PNG.',
    aed: '500',
    buyerClaim:
      'Only two usable concepts were delivered. The third is a colour variation of the ' +
      'second, not a distinct concept as the brief required.',
    sellerClaim:
      'Three concepts were delivered inside the agreed window. The client changed ' +
      'direction after seeing them.',
    evidence: [
      ['buyer', 'brief.txt', 'BRIEF\nThree distinct logo concepts, seven days, SVG and PNG.\nSigned 1 August 2026.'],
      ['seller', 'delivery-note.txt', 'DELIVERY NOTE\nTwo concepts plus a colour variation of concept 2, sent 8 August 2026.'],
    ],
  },
  {
    slug: 'scope-creep',
    expect: 'release to the seller; the extra work was never agreed',
    description: 'Five product photographs',
    terms: 'Five product photographs on a white background, delivered as JPEG at 3000px. Delivery by 20 August 2026.',
    aed: '750',
    buyerClaim:
      'The photographs are unusable. I need them on a transparent background and in ' +
      'three crops each for the web store.',
    sellerClaim:
      'Five photographs on white at 3000px were delivered on 18 August. Transparent ' +
      'backgrounds and additional crops were never part of the brief.',
    evidence: [
      ['seller', 'agreed-brief.txt', 'BRIEF\nFive product photographs, white background, JPEG, 3000px. Due 20 August 2026.'],
      ['seller', 'delivery-receipt.txt', 'DELIVERY\nFive JPEG files at 3000px on white, transferred 18 August 2026. Client acknowledged receipt.'],
    ],
  },
  {
    slug: 'late-no-penalty',
    expect: 'unclear; the contract sets a date and no consequence for missing it',
    description: 'Arabic translation of a company profile',
    terms: 'Translate a 4,000 word company profile into Arabic. Delivery by 10 August 2026.',
    aed: '900',
    buyerClaim:
      'It arrived five days late and I missed the trade licence submission I needed it for.',
    sellerClaim:
      'The full translation was delivered and the client has accepted the quality. ' +
      'The delay was four working days.',
    evidence: [
      ['buyer', 'contract.txt', 'AGREEMENT\n4,000 word company profile, English to Arabic. Delivery by 10 August 2026. No penalty clause.'],
      ['seller', 'sent.txt', 'TRANSFER LOG\nFinal Arabic translation, 4,140 words, sent 15 August 2026 09:12.'],
    ],
  },
  {
    slug: 'partial',
    expect: 'a split near 60/40; twelve of twenty is arithmetic, not judgement',
    description: 'Product photography, twenty items',
    terms: 'Photograph 20 items, two angles each, delivered as a single archive by 25 August 2026.',
    aed: '2750',
    buyerClaim: 'Only 12 of the 20 items were photographed. I paid for 20.',
    sellerClaim:
      'Twelve items were photographed. The client never sent the remaining eight ' +
      'despite three reminders.',
    evidence: [
      ['buyer', 'order.txt', 'ORDER\n20 items, two angles each, 2,750 AED total. Archive due 25 August 2026.'],
      ['seller', 'archive-manifest.txt', 'MANIFEST\n24 images, 12 items, two angles each. Items 13 to 20 not received from client.'],
    ],
  },
  {
    slug: 'one-sided',
    expect: 'escalation; silence from one side is not proof against them',
    description: 'Social media management, one month',
    terms: 'Twelve posts across Instagram and LinkedIn during August 2026, with monthly reporting.',
    aed: '1500',
    buyerClaim:
      'Four posts went out in the whole month and I never received a report. I have ' +
      'asked twice and had no reply.',
    sellerClaim: null,
    evidence: [
      ['buyer', 'post-log.txt', 'POST LOG (client record)\n3 Aug, 9 Aug, 17 Aug, 22 Aug. Four posts total. No report received.'],
    ],
  },
  {
    slug: 'no-evidence',
    expect: 'escalation; two assertions and nothing to weigh them against',
    description: 'Website maintenance retainer',
    terms: 'Monthly maintenance retainer: updates, backups and uptime monitoring for August 2026.',
    aed: '1200',
    buyerClaim: 'The site went down twice and nobody responded. I want the month refunded.',
    sellerClaim: 'The site was monitored throughout and both incidents were resolved the same day.',
    evidence: [],
  },
  {
    slug: 'contradictory',
    expect: 'escalation or low confidence; the two records cannot both be true',
    description: 'Catering for a corporate event',
    terms: 'Catering for 40 people, delivered to the venue by 18:00 on 22 August 2026.',
    aed: '3200',
    buyerClaim: 'The food arrived at 19:40, after the guests had left. The event was ruined.',
    sellerClaim: 'Delivery was completed at 17:45, fifteen minutes early. We have the venue signature.',
    evidence: [
      ['buyer', 'venue-log.txt', 'VENUE GATE LOG\n22 August 2026. Catering vehicle recorded at gate 19:38. Unloading complete 19:52.'],
      ['seller', 'delivery-slip.txt', 'DELIVERY SLIP\n22 August 2026, 17:45. Received at venue reception. Signature on file.'],
    ],
  },
  {
    slug: 'agreed-facts',
    expect: 'a confident split; both sides agree what happened',
    description: 'Exhibition stand build',
    terms:
      'Build and install an exhibition stand, complete by 09:00 on 12 September 2026. ' +
      'Late completion is deducted at 5 percent of the fee per hour.',
    aed: '4000',
    buyerClaim: 'The stand was finished at 12:00, three hours late. That is a 15 percent deduction.',
    sellerClaim:
      'We accept the stand was three hours late. We think 15 percent is harsh given the ' +
      'venue opened access late, but we do not dispute the hours.',
    evidence: [
      ['buyer', 'terms.txt', 'AGREEMENT\nStand complete 09:00, 12 September 2026. Deduction 5 percent of fee per hour late.'],
      ['seller', 'handover.txt', 'HANDOVER\nStand signed off by client representative at 12:00, 12 September 2026.'],
    ],
  },
  {
    slug: 'vague-terms',
    expect: 'escalation; there is no agreement here to measure anything against',
    description: 'A website',
    terms: 'Build a modern website for the business.',
    aed: '2200',
    buyerClaim: 'This is not what I imagined at all. It looks nothing like a modern website.',
    sellerClaim: 'A five page responsive website was delivered. The brief said modern and it is modern.',
    evidence: [
      ['seller', 'pages.txt', 'DELIVERED\nFive responsive pages: home, about, services, gallery, contact. Live 30 August 2026.'],
    ],
  },
  {
    slug: 'above-ceiling',
    expect: 'escalation on the amount alone, however good the answer is',
    description: 'Office fit-out, partial',
    terms: 'Supply and install 24 workstations and partitioning, complete by 1 September 2026.',
    aed: '12000',
    buyerClaim: 'Eighteen workstations were installed and the partitioning was never delivered.',
    sellerClaim: 'Eighteen were installed. Partitioning was cancelled by the client in writing on 20 August.',
    evidence: [
      ['buyer', 'purchase-order.txt', 'PURCHASE ORDER\n24 workstations, partitioning, 12,000 AED. Completion 1 September 2026.'],
      ['seller', 'site-report.txt', 'SITE REPORT\n18 workstations installed 29 August. Partitioning cancelled by client email 20 August.'],
    ],
  },
]

/* ------------------------------------------------------------------------ */

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split(/\r?\n/)) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY', 'ANTHROPIC_API_KEY']) {
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

const argv = process.argv.slice(2)
const seedOnly = argv.includes('--seed')
const wanted = argv.filter((a) => /^\d+$/.test(a)).map(Number)
const cases = wanted.length ? wanted.map((n) => CASES[n - 1]).filter(Boolean) : CASES

function must(label, { data, error }) {
  if (error) {
    console.error(`\n  ${label} failed: ${error.message}\n`)
    process.exit(1)
  }
  return data
}

async function actAs(email, password) {
  const client = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error } = await client.auth.signInWithPassword({ email, password })
  if (error) {
    console.error(`\n  could not sign in as ${email}: ${error.message}\n`)
    process.exit(1)
  }
  return client
}

/* ------------------------------------------------------------------------ */

console.log(`\nBench ${RUN}: ${cases.length} case(s)\n`)

const password = `${RUN}-${crypto.randomUUID()}`
const buyerEmail = `buyer.${RUN}@example.test`
const sellerEmail = `seller.${RUN}@example.test`

const buyer = must('creating the buyer',
  await db.auth.admin.createUser({ email: buyerEmail, password, email_confirm: true })).user
const seller = must('creating the seller',
  await db.auth.admin.createUser({ email: sellerEmail, password, email_confirm: true })).user

must('creating profiles', await db.from('profiles').insert([
  { id: buyer.id, full_name: 'Bench Buyer', email: buyerEmail,
    identity_verified_at: new Date().toISOString(), identity_provider: 'manual_review' },
  { id: seller.id, full_name: 'Bench Seller', email: sellerEmail,
    identity_verified_at: new Date().toISOString(), identity_provider: 'manual_review' },
]))

const asBuyer = await actAs(buyerEmail, password)
const asSeller = await actAs(sellerEmail, password)

const evidenceDeps = {
  storage: new SupabaseObjectStorage(db),
  repository: new SupabaseEvidenceRepository(db),
  clock: { now: () => new Date() },
  newId: () => crypto.randomUUID(),
}

/** Walks one case from nothing to a dispute waiting for the model. */
async function seedCase(spec) {
  const total = filsFromAed(spec.aed)

  const contract = must(`contract for ${spec.slug}`, await asBuyer
    .from('transactions')
    .insert({
      buyer_id: buyer.id,
      seller_id: seller.id,
      description: `${spec.description} [${RUN}/${spec.slug}]`,
      terms: spec.terms,
      total_amount_fils: Number(total),
      created_by: buyer.id,
    })
    .select('id, total_amount_fils')
    .single())

  for (const [event, actor] of [['submit', asBuyer], ['accept', asSeller], ['mark_delivered', asSeller]]) {
    must(`${event} on ${spec.slug}`, await actor.rpc('apply_transaction_event', {
      p_transaction_id: contract.id,
      p_event: event,
    }))
  }

  for (const [role, filename, text] of spec.evidence) {
    const filed = await uploadEvidence({
      transactionId: contract.id,
      userId: role === 'buyer' ? buyer.id : seller.id,
      filename,
      contentType: 'text/plain',
      bytes: new TextEncoder().encode(text),
      note: null,
    }, evidenceDeps)
    if (!filed.ok) {
      console.error(`\n  filing ${filename} for ${spec.slug} failed: ${filed.error.message}\n`)
      process.exit(1)
    }
  }

  must(`open_dispute on ${spec.slug}`, await asBuyer.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'open_dispute',
  }))

  const dispute = must(`dispute for ${spec.slug}`, await asBuyer
    .from('disputes')
    .insert({
      transaction_id: contract.id,
      opened_by: buyer.id,
      opened_by_role: 'buyer',
      buyer_claim: spec.buyerClaim,
      seller_claim: spec.sellerClaim,
      disputed_amount_fils: contract.total_amount_fils,
    })
    .select('id')
    .single())

  return dispute.id
}

const repository = new SupabaseDisputeRepository(db)
const model = createAnthropicClient({ apiKey: cfg.ANTHROPIC_API_KEY })
const results = []

for (const [i, spec] of cases.entries()) {
  process.stdout.write(`  ${String(i + 1).padStart(2)}. ${spec.slug.padEnd(16)}`)
  const disputeId = await seedCase(spec)

  if (seedOnly) {
    console.log(`seeded ${disputeId}`)
    continue
  }

  const started = Date.now()
  const outcome = await runResolution(disputeId, {
    repository,
    model,
    policy: POLICY,
    clock: { now: () => new Date() },
  })
  const seconds = Math.round((Date.now() - started) / 1000)

  const { data: log } = await db
    .from('ai_call_log')
    .select('id, validation_outcome, confidence, escalation_reasons, error_message')
    .eq('dispute_id', disputeId)
    .order('created_at', { ascending: false })
    .limit(1)
  const call = log?.[0]

  const { data: props } = await db
    .from('resolution_proposals')
    .select('decision, seller_amount_fils, buyer_amount_fils, ai_call_id')
    .eq('dispute_id', disputeId)
    .limit(1)
  const proposal = props?.[0]

  results.push({ spec, disputeId, outcome, call, proposal, seconds })

  const verdict = call?.validation_outcome ?? 'no audit row'
  const why = call?.escalation_reasons?.length ? ` ${JSON.stringify(call.escalation_reasons)}` : ''
  console.log(`${verdict.padEnd(22)} conf ${String(call?.confidence ?? '-').padEnd(6)} ${seconds}s${why}`)
}

if (seedOnly) {
  console.log('\nSeeded, nothing called.\n')
  process.exit(0)
}

/* ------------------------------------------------------------------------ *
 * The report.
 * ------------------------------------------------------------------------ */

const accepted = results.filter((r) => r.call?.validation_outcome === 'accepted')
const rate = results.length ? Math.round((accepted.length / results.length) * 100) : 0

console.log(`\n\nWhat happened\n`)
for (const r of results) {
  const split = r.proposal
    ? `${formatAed(Number(r.proposal.seller_amount_fils))} / ${formatAed(Number(r.proposal.buyer_amount_fils))}`
    : '—'
  console.log(`  ${r.spec.slug.padEnd(16)} ${(r.call?.validation_outcome ?? '?').padEnd(22)} ${split}`)
  console.log(`  ${' '.repeat(16)} expected: ${r.spec.expect}`)
}

console.log(`\n\nThe number\n`)
console.log(`  ${accepted.length} of ${results.length} produced a proposal the parties can see  (${rate}%)`)

const byOutcome = new Map()
for (const r of results) {
  const k = r.call?.validation_outcome ?? 'no audit row'
  byOutcome.set(k, (byOutcome.get(k) ?? 0) + 1)
}
for (const [k, n] of [...byOutcome].sort((a, b) => b[1] - a[1])) {
  console.log(`    ${String(n).padStart(2)}  ${k}`)
}

const confidences = results.map((r) => r.call?.confidence).filter((c) => typeof c === 'number')
if (confidences.length) {
  const sorted = [...confidences].sort((a, b) => a - b)
  const median = sorted[Math.floor(sorted.length / 2)]
  const nearMiss = confidences.filter((c) => c >= POLICY.minConfidence - 0.05 && c < POLICY.minConfidence)
  console.log(`\n  confidence: low ${sorted[0]}, median ${median}, high ${sorted[sorted.length - 1]}`)
  console.log(`  floor is ${POLICY.minConfidence}; ${nearMiss.length} run(s) landed within 0.05 below it`)
}

// The link 0027 added, checked on real rows rather than assumed.
const linked = results.filter((r) => r.proposal?.ai_call_id != null)
if (accepted.length) {
  console.log(`\n  ${linked.length} of ${accepted.length} stored proposal(s) name the run that produced them`)
  const wrong = results.filter((r) => r.proposal && r.call && r.proposal.ai_call_id !== r.call.id)
  if (wrong.length) console.log(`  MISMATCH on: ${wrong.map((r) => r.spec.slug).join(', ')}`)
}

console.log(`\n  Every run above is on the audit trail and can be recounted from the database.\n`)
