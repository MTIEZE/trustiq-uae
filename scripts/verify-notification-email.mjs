/**
 * Makes a contract move and watches the email about it actually leave.
 *
 *   node scripts/verify-notification-email.mjs you+notify@gmail.com
 *   node scripts/verify-notification-email.mjs you+notify@gmail.com --arabic
 *
 * This one really sends. Give it an address you can open, on a mailbox that
 * accepts plus-addressing, so it can be run again without burning addresses.
 *
 * The sender only offers rows that have sat for a grace period, so that two
 * moves in a row become one email rather than two a minute apart. Waiting five
 * minutes to find out whether this works is not a test anybody runs twice, so
 * the row is backdated with the service role before the sender is asked.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `mail-${Math.random().toString(16).slice(2, 10)}`

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_ACCESS_TOKEN']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()
const ref = new URL(cfg.SUPABASE_URL).host.split('.')[0]
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

/** app.notifications is not on the API, so backdating goes through SQL. */
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  })
  if (!r.ok) {
    console.error(`\n  SQL refused (${r.status}): ${(await r.text()).slice(0, 200)}\n`)
    process.exit(1)
  }
  return r.json()
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

/* ------------------------------------------------------------------ */

const recipientEmail = process.argv.slice(2).find((a) => !a.startsWith('--'))
const arabic = process.argv.includes('--arabic')

if (!recipientEmail) {
  console.error('\n  Give an address you can open.\n')
  process.exit(1)
}

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const senderSideEmail = `mover.${RUN}@example.test`

step(`The other party is ${recipientEmail}`)

async function makeAccount(email, name) {
  const user = must(`creating ${email}`,
    await db.auth.admin.createUser({ email, password, email_confirm: true })).user
  must(`profile for ${email}`,
    await db.from('profiles').insert({ id: user.id, full_name: name, email }))
  must(`verifying ${email}`, await db.rpc('record_manual_verification', {
    p_user_id: user.id, p_note: `Verified for the notification email check (${RUN})`,
  }))
  return user
}

const mover = await makeAccount(senderSideEmail, 'Layth Barakat')
const recipient = await makeAccount(recipientEmail, 'Mohamed Tieze')

if (arabic) {
  const asRecipient = await actAs(recipientEmail, password)
  must('choosing Arabic', await asRecipient.rpc('set_preferred_locale', { p_locale: 'ar' }))
  ok('the recipient has chosen Arabic, so the mail should be in Arabic and right to left')
}

step('A contract, sent')

const asMover = await actAs(senderSideEmail, password)
const contract = must('creating the contract', await asMover
  .from('transactions')
  .insert({
    buyer_id: mover.id,
    seller_id: recipient.id,
    description: `Brand identity for a clinic [${RUN}]`,
    terms: 'Logo, palette and two applications within ten days.',
    total_amount_fils: 260000,
    created_by: mover.id,
  })
  .select('id')
  .single())

must('submit', await asMover.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'submit',
}))
ok(`contract ${contract.id} is waiting on ${recipientEmail}`)

step('Backdating past the grace period')

await sql(`update app.notifications
           set created_at = now() - interval '1 hour'
           where transaction_id = '${contract.id}'`)

const pending = await db.rpc('notifications_to_send', {})
const mine = (pending.data ?? []).filter((r) => r.email === recipientEmail)
check('the sender now sees it', mine.length === 1, `${mine.length} row(s)`)
check('in the chosen language', mine[0]?.locale === (arabic ? 'ar' : 'en'), mine[0]?.locale)

step('Asking the deployed function to drain')

const response = await fetch(`${cfg.SUPABASE_URL}/functions/v1/send-notifications`, {
  method: 'POST',
  headers: {
    apikey: cfg.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${cfg.SUPABASE_SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
  },
  body: '{}',
})
const body = await response.text()
console.log(`  HTTP ${response.status}  ${body.slice(0, 160)}`)

check('the function answered', response.status === 200, `${response.status}`)

let counts = {}
try { counts = JSON.parse(body) } catch { /* reported by the check above */ }
check('it sent at least one', (counts.sent ?? 0) >= 1, JSON.stringify(counts))
check('and none failed', (counts.failed ?? 0) === 0, JSON.stringify(counts))

step('What the outbox says now')

const after = await sql(`select emailed_at is not null as sent, email_error
                         from app.notifications
                         where transaction_id = '${contract.id}'`)
check('the row is marked sent', after.every((r) => r.sent), JSON.stringify(after))
check('with no error recorded', after.every((r) => r.email_error === null), JSON.stringify(after))

const again = await db.rpc('notifications_to_send', {})
check('and it is not offered a second time',
  (again.data ?? []).filter((r) => r.email === recipientEmail).length === 0)

step('And the other queue: an account notice')

// A suspension is the one thing the console does to somebody that they cannot
// see in the app afterwards, because it stops them signing in. It goes out on
// its own queue, drained by the same function, and this proves the whole path
// rather than the row.
await sql(`insert into app.account_notices (recipient_id, kind, reason)
           values ('${recipient.id}', 'suspended',
                   'A test notice from verify-notification-email.mjs. Nothing has happened to your account.')`)

const waiting = await db.rpc('account_notices_to_send', {})
const notice = (waiting.data ?? []).find((r) => r.email === recipientEmail)
check('the sender sees the notice', Boolean(notice), JSON.stringify(waiting.data ?? []))

const second = await fetch(`${cfg.SUPABASE_URL}/functions/v1/send-notifications`, {
  method: 'POST',
  headers: {
    apikey: cfg.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${cfg.SUPABASE_SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
  },
  body: '{}',
})
const secondBody = await second.text()
console.log(`  HTTP ${second.status}  ${secondBody.slice(0, 160)}`)

let noticeCounts = {}
try { noticeCounts = JSON.parse(secondBody) } catch { /* reported below */ }
check('it went out', (noticeCounts.sent ?? 0) >= 1, JSON.stringify(noticeCounts))
check('with nothing failing', (noticeCounts.failed ?? 0) === 0, JSON.stringify(noticeCounts))

const drained = await db.rpc('account_notices_to_send', {})
check('and the notice left the queue',
  (drained.data ?? []).filter((r) => r.email === recipientEmail).length === 0)

console.log(failures === 0
  ? `\n  Now look in ${recipientEmail}. Subject should name one thing waiting,\n  and the body should list the contract by its description.\n`
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
