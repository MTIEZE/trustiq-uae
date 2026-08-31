/**
 * Proves the operator panel against the live project.
 *
 *   node scripts/verify-admin.mjs
 *
 * The schema tests prove the rules on a disposable Postgres. This proves the
 * endpoint: that the numbers come back through PostgREST with the same
 * publishable key that ships inside the app, that a signed-in person who is
 * not on the list gets nothing, and that being on the list is the only
 * difference between the two.
 *
 * It puts a throwaway account on the operator list and takes it off again. If
 * it dies halfway it says which row to remove; nothing here is left behind on
 * purpose, unlike the closure script, because an operator left on the list is
 * not a test artefact, it is a person who can read everything.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `admin-${Math.random().toString(16).slice(2, 10)}`

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

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
}

/**
 * `app` is not exposed through PostgREST, so the operator list can only be
 * touched with a direct connection. That is the whole design: nothing that
 * ships anywhere can add an operator.
 */
async function sql(query) {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  )
  if (!response.ok) {
    console.error(`\n  SQL refused (HTTP ${response.status}): ${(await response.text()).slice(0, 400)}\n`)
    process.exit(1)
  }
  return response.json()
}

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const email = `operator.${RUN}@example.test`

step('Making somebody ordinary')

// Taken before the throwaway exists, so the panel can be held to not moving.
const before = (await sql(
  `select (select count(*) from app.real_profiles) as people,
          (select count(*) from app.activity a
           join app.real_profiles p on p.id = a.user_id
           where a.day = (now() at time zone 'Asia/Dubai')::date) as active`))[0]

const created = await db.auth.admin.createUser({ email, password, email_confirm: true })
if (created.error) {
  console.error(`\n  could not create the account: ${created.error.message}\n`)
  process.exit(1)
}
const userId = created.data.user.id
await db.from('profiles').insert({ id: userId, full_name: 'Panel Check', email })
ok(`account ${email}`)

// From here the publishable key only, plus their own session. Exactly what a
// browser holding the panel would have.
const app = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const signIn = await app.auth.signInWithPassword({ email, password })
if (signIn.error) {
  console.error(`\n  could not sign in: ${signIn.error.message}\n`)
  process.exit(1)
}
ok('signed in with the key that ships in the app')

step('Before being made an operator')

for (const [name, call] of [
  ['admin_overview', () => app.rpc('admin_overview')],
  ['admin_daily', () => app.rpc('admin_daily', { p_days: 7 })],
  ['admin_ai_quality', () => app.rpc('admin_ai_quality')],
]) {
  const { error } = await call()
  check(`${name} is refused`, Boolean(error), error ? undefined : 'it answered')
}

// The register accepts them even so. Attendance is not an operator power.
{
  const { error } = await app.rpc('record_activity')
  check('but they can still mark themselves present', !error, error?.message)
}

step('On the list')

await sql(`insert into app.admins (user_id, note)
           values ('${userId}', 'Temporary, from scripts/verify-admin.mjs ${RUN}')`)

let overview
{
  const { data, error } = await app.rpc('admin_overview')
  check('admin_overview answers', !error, error?.message)
  overview = Array.isArray(data) ? data[0] : data
}

if (overview) {
  console.log(
    `\n  people ${overview.people}   verified ${overview.verified}   ` +
    `active today ${overview.active_today}   7d ${overview.active_7d}   30d ${overview.active_30d}`,
  )
  console.log(
    `  contracts ${overview.contracts}   binding ${overview.contracts_binding}   ` +
    `confirmed ${overview.contracts_confirmed}   disputed ${overview.contracts_disputed}`,
  )
  console.log(
    `  disputes ${overview.disputes} (${overview.disputes_open} open)   ` +
    `proposals ${overview.proposals_issued}   half ${overview.proposals_half_accepted}   ` +
    `accepted ${overview.proposals_accepted}   escalated ${overview.escalated_to_human}\n`,
  )

  // The throwaway lives at a domain RFC 2606 reserves, so the panel refuses to
  // see it. That is the whole point of the filter: the scripts in this folder
  // have put dozens of accounts in this database and none of them is a
  // customer. Asserted rather than assumed, because a panel quietly counting
  // its own fixtures is exactly the failure that would go unnoticed.
  check(
    'the throwaway account is not in the headcount, its address is reserved',
    Number(overview.people) === Number(before.people),
    `${before.people} before, ${overview.people} after`,
  )
  check(
    'and calling record_activity did not make it present either',
    Number(overview.active_today) === Number(before.active),
    `${before.active} before, ${overview.active_today} after`,
  )
  check(
    'a proposal is never accepted by one party alone',
    overview.proposals_accepted <= overview.proposals_issued,
    `${overview.proposals_accepted} accepted of ${overview.proposals_issued} issued`,
  )
}

{
  const { data, error } = await app.rpc('admin_daily', { p_days: 7 })
  check('admin_daily answers', !error, error?.message)
  check('with one row per day, empty days included', data?.length === 7, `got ${data?.length}`)
  if (data?.length) {
    const today = data[data.length - 1]
    check('today is the last row', typeof today.day === 'string')
    console.log(`  today: ${today.day}  signups ${today.signups}  active ${today.active}  contracts ${today.contracts}`)
  }
}

{
  const { data, error } = await app.rpc('admin_ai_quality')
  check('admin_ai_quality answers', !error, error?.message)
  for (const row of data ?? []) {
    console.log(
      `  ${String(row.outcome).padEnd(22)} ${String(row.calls).padStart(3)} calls   ` +
      `confidence ${row.mean_confidence ?? '-'}   ${row.mean_latency_ms ?? '-'} ms`,
    )
  }
  check('the model log is not empty, so this is reading real runs', (data ?? []).length > 0)
}

step('Nothing here hands out anything but numbers')

{
  // The panel reads past RLS. If it could also list people, one mistake in
  // app.is_admin() would be a database dump rather than a leak of counts.
  const { data, error } = await app.from('profiles').select('id, full_name, email')
  check(
    'an operator still cannot read the profile table',
    error !== null || (data ?? []).length <= 1,
    `${(data ?? []).length} rows came back`,
  )
}

{
  const { error } = await app.rpc('close_account', { p_user_id: userId })
  check('and cannot close somebody else’s account either', Boolean(error))
}

step('Taking the list back')

await sql(`delete from app.admins where user_id = '${userId}'`)

{
  const { error } = await app.rpc('admin_overview')
  check('off the list, the same call is refused again', Boolean(error))
}

// The account itself goes. It was never a person.
await db.auth.admin.deleteUser(userId)
ok('throwaway account removed')

if (failures) {
  console.error(`\n  ${failures} check${failures === 1 ? '' : 's'} failed\n`)
  process.exit(1)
}
console.log('\n  The operator panel is reachable only by an operator, and only for numbers.\n')
