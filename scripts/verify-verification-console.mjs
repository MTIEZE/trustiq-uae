/**
 * The verification queue, driven the way the console drives it.
 *
 *   node scripts/verify-verification-console.mjs
 *
 * There were already scripts covering verification, and all of them acted with
 * the service role. That is not who presses the button. An operator signs in
 * with the same publishable key that ships in the app and calls through
 * PostgREST as `authenticated`, and nothing tested that path, which is exactly
 * where it was broken: the queue listed, and deciding was refused three
 * different ways.
 *
 * Two throwaway accounts, one made an operator, and nothing left behind. An
 * operator forgotten on that list is not a test artefact, it is a person who
 * can read everything.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `console-${Math.random().toString(16).slice(2, 10)}`

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split(/\r?\n/)) {
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

async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query }),
  })
  if (!r.ok) {
    console.error(`\n  SQL refused: ${(await r.text()).slice(0, 300)}\n`)
    process.exit(1)
  }
  return r.json()
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

async function cleanUp() {
  for (const id of made) {
    await sql(`delete from app.admins where user_id = '${id}'`)
    await admin.auth.admin.deleteUser(id).catch(() => {})
  }
}

step('Two throwaway accounts, one of them an operator')

const operator = await person('operator', 'Console Reviewer')
const applicant = await person('applicant', 'Wants To Be Verified')
await sql(`insert into app.admins (user_id, note)
           values ('${operator.id}', 'Temporary, from verify-verification-console.mjs ${RUN}')`)
ok('one on the operator list, one not')

step('The applicant asks, through their own session')

{
  const { error } = await applicant.client.rpc('request_verification', {
    p_legal_name: 'Wants To Be Verified',
    p_document_kind: 'emirates_id',
    p_how: 'Happy to show it on a video call.',
  })
  check('the request is filed', !error, error?.message)
}

{
  const { data, error } = await applicant.client.rpc('my_verification')
  const row = Array.isArray(data) ? data[0] : data
  check('and they can see it is pending', !error && row?.standing === 'pending',
    error?.message ?? JSON.stringify(row))
}

step('The operator opens the queue, exactly as the console does')

let requestId = null
{
  const { data, error } = await operator.client.rpc('admin_verification_queue')
  check('the queue lists it', !error, error?.message)
  const mine = (data ?? []).find((r) => r.user_id === applicant.id)
  check('and the applicant is in it', Boolean(mine), `${(data ?? []).length} row(s)`)
  requestId = mine?.request_id ?? null
}

step('The operator approves it, exactly as the console does')

if (requestId === null) {
  console.error('\n  no request id to decide on; stopping here\n')
  await cleanUp()
  process.exit(1)
}

{
  // The old service-role path, still refused from a session and meant to be.
  // Checked here so that if somebody ever opens it up, this says so.
  const { error } = await operator.client.rpc('decide_verification', {
    p_request_id: requestId,
    p_approve: true,
    p_note: 'Approved through the script path, which must not work from here.',
  })
  check('the service-role path stays shut to an operator', Boolean(error), 'it answered')
}

{
  // Asking for more first, because that is the outcome that used to have no
  // way of being expressed at all.
  const { error } = await operator.client.rpc('admin_decide_verification', {
    p_request_id: requestId,
    p_outcome: 'needs_more_info',
    p_note: 'Please say which emirate issued the card. The number is not needed.',
  })
  check('an operator can ask for more', !error, error?.message)
}

{
  const { data } = await applicant.client.rpc('my_verification')
  const row = Array.isArray(data) ? data[0] : data
  check('the person sees the question, not a refusal', row?.standing === 'needs_more_info',
    JSON.stringify(row))
  check('with the question itself attached', (row?.reason ?? '').includes('which emirate'),
    row?.reason)
}

{
  const { error } = await applicant.client.rpc('request_verification', {
    p_legal_name: 'Wants To Be Verified',
    p_document_kind: 'emirates_id',
    p_how: 'Issued in Sharjah.',
  })
  check('and can answer it', !error, error?.message)
}

{
  const { error } = await operator.client.rpc('admin_decide_verification', {
    p_request_id: requestId,
    p_outcome: 'approved',
    p_note: 'Emirates ID shown on a call, name and photo match the account.',
  })
  check('then the decision goes through', !error, error?.message)
}

step('And the person is actually verified')

{
  const { data, error } = await applicant.client.rpc('my_verification')
  const row = Array.isArray(data) ? data[0] : data
  // 'verified' rather than 'approved': once the profile carries the stamp,
  // that is what the person is, and the request that got them there is behind
  // them. The function says so deliberately.
  check('their own view says verified', !error && row?.standing === 'verified',
    error?.message ?? JSON.stringify(row))
}

{
  const rows = await sql(
    `select identity_verified_at is not null as verified, identity_provider
     from public.profiles where id = '${applicant.id}'`)
  check('the profile carries the verification', rows[0]?.verified === true, JSON.stringify(rows[0]))
  check('stamped as a person having checked, never as UAE Pass',
    rows[0]?.identity_provider === 'manual_review', rows[0]?.identity_provider)
}

{
  const rows = await sql(
    `select count(*)::int as n from app.verification_requests
     where user_id = '${applicant.id}' and state = 'approved'`)
  check('and the request is closed as approved', rows[0]?.n === 1, JSON.stringify(rows[0]))
}

{
  const rows = await sql(
    `select kind from app.account_notices
     where recipient_id = '${applicant.id}' order by created_at`)
  const kinds = rows.map((r) => r.kind)
  check('the person was written to at each step',
    kinds.includes('verification_more_info') && kinds.includes('verification_approved'),
    JSON.stringify(kinds))
}

{
  const rows = await sql(
    `select count(*)::int as n from app.admin_access_log
     where subject_id = '${applicant.id}' and what = 'verification'`)
  check('and both decisions are on the access log', rows[0]?.n === 2, JSON.stringify(rows[0]))
}

step('Clearing up')
await cleanUp()
ok('both accounts removed and off the operator list')

if (failures) {
  console.error(`\n  ${failures} check${failures === 1 ? '' : 's'} failed\n`)
  process.exit(1)
}
console.log('\n  An operator can approve a verification from the console.\n')
