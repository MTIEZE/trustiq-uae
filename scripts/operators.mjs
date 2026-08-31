/**
 * Who may read the platform aggregates.
 *
 *   node scripts/operators.mjs                     list them
 *   node scripts/operators.mjs --add you@mail.ae   put somebody on
 *   node scripts/operators.mjs --remove you@mail.ae
 *
 * `app.admins` is not reachable through PostgREST and never will be, so this
 * goes through the management API with a direct connection. That is the whole
 * design: the list of people who can see everything cannot be edited by
 * anything that ships to a device, including by somebody already on it.
 *
 * An operator reads counts and nothing else. They cannot see a name, an email,
 * a claim or a contract, which is asserted both in the schema tests and live
 * by scripts/verify-admin.mjs. Adding somebody here is still a real decision:
 * how the business is doing is not public information.
 */

import { readFileSync } from 'node:fs'

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_ACCESS_TOKEN']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()
const ref = new URL(cfg.SUPABASE_URL).host.split('.')[0]

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
    console.error(`\n  Refused (HTTP ${response.status}): ${(await response.text()).slice(0, 500)}\n`)
    process.exit(1)
  }
  return response.json()
}

// Single quotes are the only thing that could break out of the literals below,
// and an email carrying one is a bad email rather than an attack. Refused
// outright rather than escaped, because there is no reason to accept it.
function address(value) {
  if (!value || !/^[^\s'"\\;]+@[^\s'"\\;]+\.[^\s'"\\;]+$/.test(value)) {
    console.error(`\n  "${value}" does not look like an email address.\n`)
    process.exit(1)
  }
  return value
}

const args = process.argv.slice(2)
const flag = (name) => {
  const at = args.indexOf(name)
  return at === -1 ? null : args[at + 1]
}

async function list() {
  const rows = await sql(`
    select p.email, p.full_name, a.added_at::date as since, coalesce(a.note, '') as note
    from app.admins a join public.profiles p on p.id = a.user_id
    order by a.added_at`)
  if (!rows.length) {
    console.log('\n  Nobody is an operator. The panel will refuse everyone, including you.')
    console.log('  node scripts/operators.mjs --add your@email\n')
    return
  }
  console.log('')
  for (const r of rows) {
    console.log(`  ${r.email.padEnd(34)} ${r.since}  ${r.full_name}${r.note ? `  (${r.note})` : ''}`)
  }
  console.log('')
}

const add = flag('--add')
const remove = flag('--remove')

if (add) {
  const email = address(add)
  const found = await sql(`select id, full_name from public.profiles where email = '${email}'`)
  if (!found.length) {
    console.error(`\n  No account with that address. They have to sign up in the app first.\n`)
    process.exit(1)
  }
  await sql(`insert into app.admins (user_id, note)
             values ('${found[0].id}', 'Added ${new Date().toISOString().slice(0, 10)}')
             on conflict (user_id) do nothing`)
  console.log(`\n  ${found[0].full_name} can now read the numbers.`)
  await list()
} else if (remove) {
  const email = address(remove)
  const gone = await sql(`
    delete from app.admins a
    using public.profiles p
    where p.id = a.user_id and p.email = '${email}'
    returning p.email`)
  console.log(gone.length ? `\n  ${email} is off the list.` : `\n  ${email} was not on it.`)
  await list()
} else {
  await list()
}
