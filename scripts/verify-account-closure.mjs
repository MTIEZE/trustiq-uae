/**
 * Closes two accounts, one that can go and one that cannot.
 *
 *   node scripts/verify-account-closure.mjs
 *
 * The schema tests prove the two paths. This proves the endpoint: that it acts
 * on the token rather than on anything the caller sends, that the sign-in is
 * shut and not only the profile emptied, and that the other party keeps their
 * contract either way.
 *
 * Everything it creates stays. That is the point of the feature being tested.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `close-${Math.random().toString(16).slice(2, 10)}`

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
const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const step = (t) => console.log(`\n${t}`)
const ok = (t) => console.log(`  ok  ${t}`)
let failures = 0

function must(label, { data, error }) {
  if (error) {
    console.error(`\nFAILED at: ${label}\n  ${error.message}\n`)
    process.exit(1)
  }
  return data
}

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
}

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`

async function signIn(email) {
  const client = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data, error } = await client.auth.signInWithPassword({ email, password })
  return { client, session: data?.session, error }
}

async function makeAccount(email, name, { verified = true } = {}) {
  const user = must(`creating ${email}`,
    await db.auth.admin.createUser({ email, password, email_confirm: true })).user
  must(`profile for ${email}`,
    await db.from('profiles').insert({ id: user.id, full_name: name, email }))
  // Verification writes an append-only identity check, and that alone holds
  // the profile in place. An abandoned signup has none, which is the whole
  // reason the deleted path exists.
  if (verified) {
    must(`verifying ${email}`, await db.rpc('record_manual_verification', {
      p_user_id: user.id, p_note: `Verified for the closure check (${RUN})`,
    }))
  }
  return user
}

async function closeAs(token) {
  const r = await fetch(`${cfg.SUPABASE_URL}/functions/v1/close-account`, {
    method: 'POST',
    headers: {
      apikey: cfg.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  })
  return { status: r.status, body: await r.text() }
}

/* ------------------------------------------------------------------ */

step('Nobody at all can call it')

const anonymous = await fetch(`${cfg.SUPABASE_URL}/functions/v1/close-account`, {
  method: 'POST',
  headers: { apikey: cfg.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ userId: '00000000-0000-0000-0000-000000000000' }),
})
check('a caller with no session is refused', anonymous.status === 401, `${anonymous.status}`)

step('Somebody who signed up and did nothing')

const quiet = `quiet.${RUN}@example.test`
const quietUser = await makeAccount(quiet, 'Quiet Person', { verified: false })
const quietSession = await signIn(quiet)

const first = await closeAs(quietSession.session.access_token)
console.log(`  HTTP ${first.status}  ${first.body}`)
check('the endpoint answers', first.status === 200)
check('and says the account was really deleted',
  JSON.parse(first.body || '{}').outcome === 'deleted', first.body)

// By id, not by address. The first version of this asked for the old email,
// which the tombstone path replaces, so it passed on an account that had only
// been anonymised.
const gone = await db.from('profiles').select('id').eq('id', quietUser.id)
check('the profile row is gone', (gone.data ?? []).length === 0,
  JSON.stringify(gone.data))

const backIn = await signIn(quiet)
check('and they cannot sign in again', Boolean(backIn.error), backIn.error?.message)

step('Somebody a contract points at')

const leaverEmail = `leaver.${RUN}@example.test`
const stayerEmail = `stayer.${RUN}@example.test`
const leaver = await makeAccount(leaverEmail, 'Departing Freelancer')
const stayer = await makeAccount(stayerEmail, 'Remaining Client')

const asStayer = (await signIn(stayerEmail)).client
const contract = must('creating the contract', await asStayer
  .from('transactions')
  .insert({
    buyer_id: stayer.id,
    seller_id: leaver.id,
    description: `Illustration set [${RUN}]`,
    terms: 'Ten illustrations within two weeks.',
    total_amount_fils: 90000,
    created_by: stayer.id,
  })
  .select('id')
  .single())
must('submit', await asStayer.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'submit',
}))
ok(`contract ${contract.id}`)

const leaverSession = await signIn(leaverEmail)
const second = await closeAs(leaverSession.session.access_token)
console.log(`  HTTP ${second.status}  ${second.body}`)

const answer = JSON.parse(second.body || '{}')
check('the endpoint answers', second.status === 200)
check('and says the profile was emptied rather than removed',
  answer.outcome === 'anonymised', second.body)
check('telling them in words what is being kept and why',
  typeof answer.kept === 'string' && answer.kept.includes('contracts you were party to'),
  answer.kept)

const tomb = must('reading the profile back',
  await db.from('profiles').select('full_name, email, identity_verified_at').eq('id', leaver.id).single())
check('the name is gone', tomb.full_name === 'Closed account', tomb.full_name)
check('the address can never be delivered to', tomb.email.endsWith('@deleted.invalid'), tomb.email)
check('and the verification went with the person', tomb.identity_verified_at === null)

const stillIn = await signIn(leaverEmail)
check('they cannot sign in with the old address', Boolean(stillIn.error), stillIn.error?.message)

step('What the other party keeps')

const theirs = must('the client reads their contract', await asStayer
  .from('transactions').select('id, state, seller_id').eq('id', contract.id).single())
check('the contract is still there', theirs.id === contract.id)
check('and still points at the person who is gone', theirs.seller_id === leaver.id)

const seen = must('the client sees the counterparty', await asStayer
  .from('visible_profiles').select('full_name').eq('id', leaver.id).single())
check('who now reads as a closed account rather than by name',
  seen.full_name === 'Closed account', seen.full_name)

console.log(failures === 0
  ? '\nSomebody can leave without taking the other party\'s record with them.\n'
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
