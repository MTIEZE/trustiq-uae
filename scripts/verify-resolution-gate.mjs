/**
 * Proves the gate on the live project, without spending a model call.
 *
 *   node scripts/verify-resolution-gate.mjs
 *
 * Only the refusals, on purpose. They are the logic that is new, and they are
 * free. A successful run costs an Opus call against a small balance, and the
 * pipeline itself has already been proven five times; what had never been
 * proven is that the edge function turns somebody away before it starts.
 *
 * To spend one and see the whole thing work, the same scene is left behind
 * with its id printed, and the last line says the command.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `gate-${Math.random().toString(16).slice(2, 10)}`

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()
const admin = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const step = (t) => console.log(`\n${t}`)
const ok = (t) => console.log(`  ok  ${t}`)
let failures = 0
const made = []

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
}

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`

async function person(tag, name) {
  const email = `${tag}.${RUN}@example.test`
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
  if (created.error) {
    console.error(`\n  could not create ${email}: ${created.error.message}\n`)
    process.exit(1)
  }
  const id = created.data.user.id
  made.push(id)
  await admin.from('profiles').insert({ id, full_name: name, email })
  const client = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  await client.auth.signInWithPassword({ email, password })
  return { id, email, client }
}

/** Straight at the edge function, as a phone would, with that person's token. */
async function callFunction(who, disputeId) {
  const token = (await who.client.auth.getSession()).data.session.access_token
  const response = await fetch(`${cfg.SUPABASE_URL}/functions/v1/resolve-dispute`, {
    method: 'POST',
    headers: {
      apikey: cfg.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ disputeId }),
  })
  return { status: response.status, body: await response.json().catch(() => ({})) }
}

step('A contract that became binding between two verified people')

const buyer = await person('buyer', 'Asking Party')
const seller = await person('seller', 'Other Side')
const stranger = await person('stranger', 'Nothing To Do With It')

for (const who of [buyer, seller]) {
  await admin.rpc('record_manual_verification', {
    p_user_id: who.id,
    p_note: `Verified inside scripts/verify-resolution-gate.mjs (${RUN}).`,
  })
}
ok('both verified, which is the only way a contract can become binding')

const contract = await admin.from('transactions').insert({
  buyer_id: buyer.id,
  seller_id: seller.id,
  description: `Gate check [${RUN}]`,
  terms: 'A fixed scope, delivered in one go.',
  total_amount_fils: 80000,
  created_by: buyer.id,
}).select('id').single()
const contractId = contract.data.id

await buyer.client.rpc('apply_transaction_event',
  { p_transaction_id: contractId, p_event: 'submit' })
await seller.client.rpc('apply_transaction_event',
  { p_transaction_id: contractId, p_event: 'accept' })
await buyer.client.rpc('apply_transaction_event',
  { p_transaction_id: contractId, p_event: 'open_dispute' })

const dispute = await buyer.client.from('disputes').insert({
  transaction_id: contractId,
  opened_by: buyer.id,
  opened_by_role: 'buyer',
  buyer_claim: 'The work delivered is not what the terms describe.',
  disputed_amount_fils: 80000,
}).select('id').single()
const disputeId = dispute.data.id

await seller.client.rpc('submit_counter_claim', {
  p_transaction_id: contractId,
  p_claim: 'The terms were met and the buyer changed their mind afterwards.',
}).then(() => {}, () => {
  // Older name, or the column written directly. Either way the claim is not
  // what this script is testing.
})
ok(`dispute ${disputeId} is open`)

step('A party who is verified may ask')

{
  const { data } = await buyer.client.rpc('may_request_resolution', { p_dispute_id: disputeId })
  const verdict = Array.isArray(data) ? data[0] : data
  check('the database says yes', verdict?.allowed === true, JSON.stringify(verdict))
}

step('A stranger is told nothing')

{
  const { data } = await stranger.client.rpc('may_request_resolution', { p_dispute_id: disputeId })
  const verdict = Array.isArray(data) ? data[0] : data
  check('the database refuses them', verdict?.allowed === false)
  check('and calls it not_found, never not_verified', verdict?.reason === 'not_found',
    verdict?.reason)

  const called = await callFunction(stranger, disputeId)
  check('the edge function answers 404', called.status === 404, `HTTP ${called.status}`)
  check('with nothing that confirms the dispute exists',
    !JSON.stringify(called.body).includes('verified'), JSON.stringify(called.body))
}

step('A verification withdrawn after the contract became binding')

await admin.rpc('revoke_verification', {
  p_user_id: buyer.id,
  p_note: 'The Emirates ID given at signup belongs to somebody else.',
})
ok('the buyer is no longer verified')

{
  const { data } = await buyer.client.rpc('may_request_resolution', { p_dispute_id: disputeId })
  const verdict = Array.isArray(data) ? data[0] : data
  check('the database now refuses them', verdict?.allowed === false)
  check('and says why, because it is theirs to fix', verdict?.reason === 'not_verified',
    verdict?.reason)
}

{
  // The one that matters. A screen-only rule would be bypassed by exactly this
  // call, made with curl and a valid session.
  const called = await callFunction(buyer, disputeId)
  check('the edge function refuses the same call, 403', called.status === 403,
    `HTTP ${called.status} ${JSON.stringify(called.body)}`)
  check('with a reason code the app can act on', called.body?.reason === 'not_verified')
}

{
  const { data } = await admin
    .from('disputes').select('state').eq('id', disputeId).single()
  check('and the dispute has not moved, so nothing was spent',
    data?.state === 'open', data?.state)
}

{
  const { count } = await admin
    .from('ai_call_log')
    .select('id', { count: 'exact', head: true })
    .eq('dispute_id', disputeId)
  check('no model call was logged against it', (count ?? 0) === 0, `${count} rows`)
}

step('Putting the buyer back, so the scene is usable')

await admin.rpc('record_manual_verification', {
  p_user_id: buyer.id,
  p_note: `Restored after the withdrawal path in scripts/verify-resolution-gate.mjs (${RUN}).`,
})

if (failures) {
  console.error(`\n  ${failures} check${failures === 1 ? '' : 's'} failed\n`)
  process.exit(1)
}

console.log(`
  Refused before anything was spent, by the server, on the call a screen
  cannot protect.

  The scene is left in place. To spend one Opus call and watch the whole thing
  run, sign in as ${buyer.email} and press the button, or:

    node scripts/run-resolution.mjs ${disputeId}
`)
