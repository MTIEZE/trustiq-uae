/**
 * The reviewer's console.
 *
 *   node scripts/review-console.mjs queue
 *   node scripts/review-console.mjs show   <disputeId>
 *   node scripts/review-console.mjs claim  <disputeId>
 *   node scripts/review-console.mjs resolve <disputeId> \
 *     --seller 440 --buyer 360 \
 *     --summary "Twenty two of forty photographs were delivered." \
 *     --finding "The brief specified forty photographs.|<evidenceId>"
 *
 * Credentials come from the environment, not from .env:
 *
 *   TRUSTIQ_REVIEWER_EMAIL=review@trustiq.ae
 *   TRUSTIQ_REVIEWER_PASSWORD=...
 *
 * **This signs in as a person and holds no service-role key.** That is the
 * whole design. Staff tooling built on a key that bypasses row level security
 * means every reviewer can read every contract in the system; here a reviewer
 * sees escalated cases and nothing else, because the database decides, exactly
 * as it does for a buyer. If a query below returns nothing, that is a policy
 * answering, not a bug to work around.
 *
 * What a reviewer deliberately cannot see: who the parties are. Roles, claims,
 * evidence and history, never names. A decision about 500 AED should not turn
 * on whose name is on the contract.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'
import { filsFromAed, formatAed } from '../packages/core/dist/index.js'

/* ------------------------------------------------------------------ */

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (!out[k]) die(`${k} is not set in .env`)
  }
  return out
}

function die(message) {
  console.error(`\n  ${message}\n`)
  process.exit(1)
}

const cfg = env()

const email = process.env.TRUSTIQ_REVIEWER_EMAIL
const password = process.env.TRUSTIQ_REVIEWER_PASSWORD
if (!email || !password) {
  die(
    'Set TRUSTIQ_REVIEWER_EMAIL and TRUSTIQ_REVIEWER_PASSWORD.\n' +
      '  They are not read from .env on purpose: this is a person signing in, ' +
      'not a service credential the repository should carry.',
  )
}

const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const { error: signInError } = await db.auth.signInWithPassword({ email, password })
if (signInError) die(`Could not sign in as ${email}: ${signInError.message}`)

/* ------------------------------------------------------------------ */

const [command, disputeId] = process.argv.slice(2)

function flag(name) {
  const at = process.argv.indexOf(`--${name}`)
  return at === -1 ? null : process.argv[at + 1]
}

function flags(name) {
  const out = []
  for (let i = 0; i < process.argv.length; i += 1) {
    if (process.argv[i] === `--${name}`) out.push(process.argv[i + 1])
  }
  return out
}

const STATE_WORDS = {
  escalated: 'waiting for a reviewer',
  human_review: 'being reviewed',
  resolved_by_human: 'decided',
}

/* ------------------------------------------------------------------ */

async function queue() {
  const { data, error } = await db
    .from('disputes')
    .select('id, state, opened_by_role, disputed_amount_fils, opened_at, claimed_at, reviewer_id')
    .order('opened_at')

  if (error) die(`Could not read the queue: ${error.message}`)
  if (!data.length) {
    console.log('\n  Nothing is waiting for a reviewer.\n')
    return
  }

  const me = (await db.auth.getUser()).data.user?.id

  console.log('')
  for (const d of data) {
    const held = d.reviewer_id === null
      ? ''
      : d.reviewer_id === me
        ? '  (yours)'
        : '  (held by another reviewer)'
    console.log(
      `  ${d.id}  ${formatAed(Number(d.disputed_amount_fils)).padStart(12)}  ` +
        `${(STATE_WORDS[d.state] ?? d.state).padEnd(22)}  opened by the ${d.opened_by_role}${held}`,
    )
  }
  console.log(`\n  ${data.length} case(s). Read one with:  show <disputeId>\n`)
}

async function show(id) {
  if (!id) die('Give a dispute id.')

  const { data: dispute, error } = await db
    .from('disputes')
    .select('id, transaction_id, state, opened_by_role, buyer_claim, seller_claim, disputed_amount_fils, opened_at')
    .eq('id', id)
    .maybeSingle()

  if (error) die(`Could not read the case: ${error.message}`)
  if (!dispute) {
    die(
      'No such case, or it is not one a reviewer may see. ' +
        'A dispute is only visible from the moment it needs a human.',
    )
  }

  const { data: contract } = await db
    .from('transactions')
    .select('description, terms, total_amount_fils, state')
    .eq('id', dispute.transaction_id)
    .maybeSingle()

  const { data: evidence } = await db
    .from('evidence')
    .select('id, filename, content_type, uploaded_by_role, uploaded_at, sha256, note, extracted_text, extraction_status')
    .eq('transaction_id', dispute.transaction_id)
    .order('uploaded_at')

  const { data: history } = await db
    .from('transaction_events')
    .select('event, actor, occurred_at')
    .eq('transaction_id', dispute.transaction_id)
    .order('occurred_at')

  const { data: proposals } = await db
    .from('resolution_proposals')
    .select('id, source, decision, summary, seller_amount_fils, buyer_amount_fils, confidence, issued_at')
    .eq('dispute_id', id)
    .order('issued_at')

  console.log(`
CASE ${dispute.id}
  state          ${STATE_WORDS[dispute.state] ?? dispute.state}
  amount         ${formatAed(Number(dispute.disputed_amount_fils))}
  opened         ${dispute.opened_at} by the ${dispute.opened_by_role}

CONTRACT
  ${contract?.description ?? '(not visible)'}
  worth          ${contract ? formatAed(Number(contract.total_amount_fils)) : '?'}
  terms          ${contract?.terms ?? ''}

BUYER SAYS
  ${dispute.buyer_claim || '(nothing recorded)'}

SELLER SAYS
  ${dispute.seller_claim || '(no answer)'}
`)

  console.log(`EVIDENCE (${evidence?.length ?? 0})`)
  for (const e of evidence ?? []) {
    console.log(`  ${e.id}`)
    console.log(`    ${e.filename}  (${e.content_type}, filed by the ${e.uploaded_by_role})`)
    console.log(`    sha256 ${e.sha256}`)
    if (e.note) console.log(`    note: ${e.note}`)
    if (e.extraction_status === 'extracted' || e.extraction_status === 'truncated') {
      const body = e.extracted_text.split('\n').map((l) => `      ${l}`).join('\n')
      console.log(`    contents${e.extraction_status === 'truncated' ? ' (truncated)' : ''}:`)
      console.log(body)
    } else {
      // Said plainly, because the two are different facts about the case.
      console.log(
        `    contents: none (${
          e.extraction_status === 'failed'
            ? 'this file should have been readable and was not'
            : e.extraction_status === 'unsupported'
              ? 'this file type is not read as text'
              : 'filed before text extraction existed'
        })`,
      )
    }
    console.log('')
  }

  console.log('HISTORY')
  for (const h of history ?? []) {
    console.log(`  ${h.occurred_at.slice(0, 19).replace('T', ' ')}  ${h.event.padEnd(18)} by ${h.actor}`)
  }

  if (proposals?.length) {
    console.log('\nWHAT WAS PROPOSED BEFORE')
    for (const p of proposals) {
      console.log(
        `  ${p.source === 'human' ? 'a reviewer' : `the model (${p.confidence} confidence)`}: ` +
          `${p.decision}, seller ${formatAed(Number(p.seller_amount_fils))}, ` +
          `buyer ${formatAed(Number(p.buyer_amount_fils))}`,
      )
      console.log(`    ${p.summary}`)
    }
  }
  console.log('')
}

async function claim(id) {
  if (!id) die('Give a dispute id.')
  const { error } = await db.rpc('claim_dispute', { p_dispute_id: id })
  if (error) die(`Could not claim the case: ${error.message}`)
  console.log(`\n  Claimed. The case is yours and no other reviewer can take it.\n`)
}

async function resolve(id) {
  if (!id) die('Give a dispute id.')

  const summary = flag('summary')
  const sellerAed = flag('seller')
  const buyerAed = flag('buyer')

  if (!summary) die('Give --summary. It is the reasoning both parties will read.')
  if (sellerAed === null || buyerAed === null) {
    die('Give --seller and --buyer, in AED. The database checks that they add up.')
  }

  // Parsed by the domain, from the text as typed. Nothing here holds a float,
  // and a value the domain refuses never becomes a decision.
  let seller
  let buyer
  try {
    seller = filsFromAed(sellerAed)
    buyer = filsFromAed(buyerAed)
  } catch (e) {
    die(`That is not an amount: ${e.message}`)
  }

  const decision = seller === 0 ? 'refund_to_buyer' : buyer === 0 ? 'release_to_seller' : 'split'

  const findings = flags('finding').map((raw) => {
    const [statement, ids] = raw.split('|')
    return {
      statement: statement.trim(),
      evidenceIds: (ids ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    }
  })

  const { data, error } = await db.rpc('issue_human_resolution', {
    p_dispute_id: id,
    p_decision: decision,
    p_summary: summary,
    p_seller_amount_fils: seller,
    p_buyer_amount_fils: buyer,
    p_findings: findings,
  })

  if (error) die(`The decision was refused: ${error.message}`)

  console.log(`
  Recorded as ${decision}.
    seller  ${formatAed(seller)}
    buyer   ${formatAed(buyer)}
    proposal ${data}

  The case is closed and the contract is resolved. The parties are not asked
  to accept: a reviewer is the escalation, not another proposal to argue with.
`)
}

/* ------------------------------------------------------------------ */

switch (command) {
  case 'queue':
    await queue()
    break
  case 'show':
    await show(disputeId)
    break
  case 'claim':
    await claim(disputeId)
    break
  case 'resolve':
    await resolve(disputeId)
    break
  default:
    console.log(`
  node scripts/review-console.mjs queue
  node scripts/review-console.mjs show    <disputeId>
  node scripts/review-console.mjs claim   <disputeId>
  node scripts/review-console.mjs resolve <disputeId> --seller <aed> --buyer <aed>
                                          --summary "..." [--finding "text|evidenceId,..."]
`)
}

await db.auth.signOut()
