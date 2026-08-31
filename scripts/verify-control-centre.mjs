/**
 * Proves the control centre against the live project.
 *
 *   node scripts/verify-control-centre.mjs
 *
 * The schema tests prove the rules on a disposable Postgres. This proves the
 * endpoint: that an operator reaches these through PostgREST with the same
 * publishable key that ships inside the app, that looking at somebody leaves a
 * trace, and that the operator cannot read the trace.
 *
 * It puts two throwaway accounts on and off the operator list. Nothing is left
 * behind: an operator forgotten on that list is not a test artefact, it is a
 * person who can read everything.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `centre-${Math.random().toString(16).slice(2, 10)}`

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

/** `app` is not exposed through PostgREST, so the list is SQL only. */
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

const operator = await person('operator', 'Console Check')
const subject = await person('subject', 'Someone Watched')
await sql(`insert into app.admins (user_id, note)
           values ('${operator.id}', 'Temporary, from verify-control-centre.mjs ${RUN}')`)
ok('one on the operator list, one not')

step('Before anything: the subject cannot reach any of it')

for (const [name, call] of [
  ['admin_people', () => subject.client.rpc('admin_people', {})],
  ['admin_person', () => subject.client.rpc('admin_person', { p_user_id: subject.id })],
  ['admin_disputes', () => subject.client.rpc('admin_disputes')],
  ['admin_activity', () => subject.client.rpc('admin_activity', { p_limit: 5 })],
]) {
  const { error } = await call()
  check(`${name} is refused`, Boolean(error), error ? undefined : 'it answered')
}

step('Looking at somebody leaves a trace')

const before = (await sql(
  `select count(*)::int as n from app.admin_access_log where actor_id = '${operator.id}'`))[0].n

{
  const { data, error } = await operator.client.rpc('admin_person', { p_user_id: subject.id })
  check('the operator can open a file', !error, error?.message)
  const row = Array.isArray(data) ? data[0] : data
  check('and it carries the details a support question needs',
    row?.email === subject.email, JSON.stringify(row))
}

{
  const { error } = await operator.client.rpc('admin_people', { p_query: 'Someone Watched' })
  check('and can search', !error, error?.message)
}

const log = await sql(
  `select what, query, subject_id from app.admin_access_log
   where actor_id = '${operator.id}' order by looked_at`)

check('two reads, two rows', log.length - before === 2, `${log.length - before} written`)
check('the file view names who was looked at',
  log.some((r) => r.what === 'person' && r.subject_id === subject.id))
check('the search records what was typed',
  log.some((r) => r.what === 'people' && r.query === 'Someone Watched'),
  JSON.stringify(log.map((r) => r.query)))

step('And the audited cannot read the audit')

{
  const { error } = await operator.client.rpc('admin_access_history', { p_days: 7 })
  check('an operator cannot read the access log', Boolean(error), error?.message)
}

{
  const { data, error } = await admin.rpc('admin_access_history', { p_days: 1 })
  check('somebody with the service role can', !error, error?.message)
  check('and sees who looked at whom',
    (data ?? []).some((r) => r.actor === operator.email && r.subject === subject.email))
}

step('Suspending, and what it refuses')

{
  const { error } = await operator.client.rpc('admin_set_suspended', {
    p_user_id: subject.id, p_suspended: true, p_reason: 'no',
  })
  check('a suspension with no real reason is refused', Boolean(error))
}

{
  const { error } = await operator.client.rpc('admin_set_suspended', {
    p_user_id: operator.id, p_suspended: true, p_reason: 'Locking myself out by accident.',
  })
  check('an operator cannot suspend themselves', Boolean(error), error?.message)
}

{
  const { error } = await operator.client.rpc('admin_set_suspended', {
    p_user_id: subject.id, p_suspended: true,
    p_reason: `Signed up with somebody else's document (${RUN}).`,
  })
  check('an ordinary account can be suspended', !error, error?.message)
}

{
  // The point of suspension, tested by trying it rather than by reading a flag.
  const shut = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error } = await shut.auth.signInWithPassword({
    email: subject.email, password,
  })
  check('and they can no longer sign in', Boolean(error), error ? undefined : 'they got in')
}

{
  const { error } = await operator.client.rpc('admin_set_suspended', {
    p_user_id: subject.id, p_suspended: false, p_reason: 'Cleared; it was their own document.',
  })
  check('and it can be lifted', !error, error?.message)

  const back = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const signIn = await back.auth.signInWithPassword({ email: subject.email, password })
  check('after which signing in works again', !signIn.error, signIn.error?.message)
}

step('The rest of the console')

for (const [name, call] of [
  ['admin_verification_queue', () => operator.client.rpc('admin_verification_queue')],
  ['admin_disputes', () => operator.client.rpc('admin_disputes')],
  ['admin_activity', () => operator.client.rpc('admin_activity', { p_limit: 20 })],
  ['admin_beta_waiting', () => operator.client.rpc('admin_beta_waiting')],
]) {
  const { error } = await call()
  check(`${name} answers`, !error, error?.message)
}

{
  const { data } = await operator.client.rpc('admin_activity', { p_limit: 50 })
  const names = (data ?? []).map((r) => `${r.detail} ${r.actor}`).join(' ')
  check('the activity feed carries no names, only roles and event codes',
    !names.includes('@') && !names.includes('Someone Watched'))
}

step('Clearing up')
await cleanUp()
ok('both accounts removed and off the operator list')

if (failures) {
  console.error(`\n  ${failures} check${failures === 1 ? '' : 's'} failed\n`)
  process.exit(1)
}
console.log('\n  An operator can act, and cannot act unseen.\n')
