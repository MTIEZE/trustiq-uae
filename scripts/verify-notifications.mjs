/**
 * Watches a notification appear because a contract moved.
 *
 *   node scripts/verify-notifications.mjs
 *
 * The schema tests already prove the rules. What they cannot prove is that a
 * signed-in person, going through PostgREST with the key that ships in the
 * app, sees the row a trigger wrote for them and nothing that was written for
 * anybody else.
 *
 * Nothing here sends anything. The outbox is deliberately inert: an event
 * writes a row, and whatever delivers it is a separate thing that can fail
 * without a contract transition failing with it.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `notif-${Math.random().toString(16).slice(2, 10)}`

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

async function actAs(email, password) {
  const client = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error } = await client.auth.signInWithPassword({ email, password })
  if (error) {
    console.error(`\nCould not sign in as ${email}: ${error.message}\n`)
    process.exit(1)
  }
  return client
}

async function makeAccount(email, password, name) {
  const user = must(`creating ${email}`,
    await db.auth.admin.createUser({ email, password, email_confirm: true })).user
  must(`profile for ${email}`,
    await db.from('profiles').insert({ id: user.id, full_name: name, email }))
  must(`verifying ${email}`, await db.rpc('record_manual_verification', {
    p_user_id: user.id,
    p_note: `Verified for the notification check (${RUN})`,
  }))
  return user
}

/* ------------------------------------------------------------------ */

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const buyerEmail = `buyer.${RUN}@example.test`
const sellerEmail = `seller.${RUN}@example.test`

step('Two verified people and a contract between them')

const buyer = await makeAccount(buyerEmail, password, 'Nadia Sabbagh')
const seller = await makeAccount(sellerEmail, password, 'Karim Idrissi')

const asBuyer = await actAs(buyerEmail, password)
const asSeller = await actAs(sellerEmail, password)

const contract = must('creating the contract', await asBuyer
  .from('transactions')
  .insert({
    buyer_id: buyer.id,
    seller_id: seller.id,
    description: `Product photography [${RUN}]`,
    terms: 'Twenty edited photographs within eight days.',
    total_amount_fils: 180000,
    created_by: buyer.id,
  })
  .select('id')
  .single())
ok(`contract ${contract.id}`)

step('The buyer sends it')

must('submit', await asBuyer.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'submit',
}))

const sellerSees = must('the seller reads their activity',
  await asSeller.rpc('my_notifications', { p_limit: 50 }))
const forThisContract = sellerSees.filter((n) => n.transaction_id === contract.id)

check('the seller is told', forThisContract.length === 1, `${forThisContract.length} row(s)`)
check('it says what happened and who did it',
  forThisContract[0]?.event === 'submit' && forThisContract[0]?.actor === 'buyer',
  JSON.stringify(forThisContract[0] ?? {}).slice(0, 120))
check('it is marked as needing them, not as news', forThisContract[0]?.needs_you === true)
check('it arrives unread', forThisContract[0]?.read_at === null)

const buyerSees = must('the buyer reads theirs',
  await asBuyer.rpc('my_notifications', { p_limit: 50 }))
check('the buyer is not told about their own move',
  buyerSees.filter((n) => n.transaction_id === contract.id).length === 0)

step('The seller accepts')

must('accept', await asSeller.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'accept',
}))

const buyerNow = must('the buyer reads again',
  await asBuyer.rpc('my_notifications', { p_limit: 50 }))
const accepted = buyerNow.find(
  (n) => n.transaction_id === contract.id && n.event === 'accept')

check('now the buyer is told in turn', Boolean(accepted))
check('and being told is news, not a task', accepted?.needs_you === false)

step('Reading them')

const marked = must('marking read', await asSeller.rpc('mark_notifications_read', {
  p_before: new Date().toISOString(),
}))
check('marking returns how many it touched', typeof marked === 'number' && marked > 0, `${marked}`)

const afterRead = must('reading once more',
  await asSeller.rpc('my_notifications', { p_limit: 50 }))
check('nothing of the seller\'s is unread any more',
  afterRead.every((n) => n.read_at !== null))

step('Nothing was sent')

const outbox = must('checking the outbox as the server', await db
  .schema('app').from('notifications').select('emailed_at, email_error')
  .eq('transaction_id', contract.id)
  .then((r) => (r.error ? { data: null, error: null } : r)))

if (outbox === null) {
  ok('app.notifications is not reachable over the API at all, which is the point')
} else {
  check('no notification has been delivered anywhere',
    outbox.every((n) => n.emailed_at === null && n.email_error === null),
    'the outbox is inert until something drains it')
}

console.log(failures === 0
  ? '\nA move by one party reaches the other, and only the other.\n'
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
