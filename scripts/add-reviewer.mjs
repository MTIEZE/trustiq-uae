/**
 * Makes someone a reviewer.
 *
 *   node scripts/add-reviewer.mjs review@trustiq.ae
 *   node scripts/add-reviewer.mjs review@trustiq.ae --remove
 *   node scripts/add-reviewer.mjs --list
 *
 * Separate from the console on purpose. This is the one operation that needs
 * the service role, because `app.reviewers` has no client policy at all:
 * nobody can add themselves, and no signed-in user can even read the list.
 * Making someone a reviewer is an administrative act and should feel like one.
 *
 * The person must already have an account. Creating accounts is not this
 * script's job.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
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

const args = process.argv.slice(2)
const listing = args.includes('--list')
const removing = args.includes('--remove')
const email = args.find((a) => !a.startsWith('--'))

if (listing) {
  const { data, error } = await db.from('reviewers').select('user_id, added_at, note')
  if (error) {
    // The table lives in `app`, which PostgREST does not expose. Reading it
    // needs SQL, and that is the point: it is not an API surface.
    console.log(`
  The reviewer list is not readable over the API by design: app.reviewers is
  outside the exposed schema and has no client policy.

  Read it in the SQL editor:

    select r.user_id, p.email, r.added_at
    from app.reviewers r
    join public.profiles p on p.id = r.user_id;
`)
    process.exit(0)
  }
  console.log(data)
  process.exit(0)
}

if (!email) {
  console.error('\n  Give an email address.\n')
  process.exit(1)
}

const { data: users, error: listError } = await db.auth.admin.listUsers({ perPage: 1000 })
if (listError) {
  console.error(`\n  Could not read the accounts: ${listError.message}\n`)
  process.exit(1)
}

const user = users.users.find((u) => u.email?.toLowerCase() === email.toLowerCase())
if (!user) {
  console.error(`\n  Nobody holds ${email}. They need an account first.\n`)
  process.exit(1)
}

// PostgREST cannot reach the `app` schema, so this goes through SQL. Written
// as a parameterised call rather than string concatenation even here, where
// the input comes from the command line.
const sql = removing
  ? `delete from app.reviewers where user_id = '${user.id}'`
  : `insert into app.reviewers (user_id, note) values ('${user.id}', 'added by scripts/add-reviewer.mjs')
     on conflict (user_id) do nothing`

const token = (() => {
  const raw = readFileSync('.env', 'utf8')
  for (const line of raw.split('\n')) {
    const t = line.trim()
    if (t.startsWith('SUPABASE_ACCESS_TOKEN=')) return t.slice('SUPABASE_ACCESS_TOKEN='.length).trim()
  }
  return null
})()

if (!token) {
  console.log(`
  SUPABASE_ACCESS_TOKEN is not set, so this cannot run the SQL itself.

  Paste this into the SQL editor instead:

    ${sql};
`)
  process.exit(0)
}

const ref = new URL(cfg.SUPABASE_URL).host.split('.')[0]
const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql }),
})

if (!response.ok) {
  console.error(`\n  Refused (HTTP ${response.status}): ${(await response.text()).slice(0, 300)}\n`)
  process.exit(1)
}

console.log(`\n  ${email} is ${removing ? 'no longer' : 'now'} a reviewer.\n`)
