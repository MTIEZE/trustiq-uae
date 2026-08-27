/**
 * Applies one migration file to the live project.
 *
 *   node scripts/apply-migration.mjs supabase/migrations/0014_....sql
 *   node scripts/apply-migration.mjs --list
 *
 * There is no `supabase db push` here because the project was not linked with
 * the CLI, so migrations go through the management API, which runs SQL against
 * the project database. The token comes from .env and is never printed.
 *
 * This applies one named file. It does not track what has run: --list reads
 * back which of our functions and tables exist so the answer comes from the
 * database rather than from a local ledger that can drift.
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

async function run(query) {
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
    console.error(`\n  Refused (HTTP ${response.status}): ${(await response.text()).slice(0, 600)}\n`)
    process.exit(1)
  }
  return response.json()
}

const args = process.argv.slice(2)

if (args.includes('--list')) {
  const rows = await run(`
    select 'function' as kind, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app')
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    union all
    select 'table', c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'app') and c.relkind in ('r', 'v')
    order by 1, 2`)
  for (const r of rows) console.log(`  ${r.kind.padEnd(9)} ${r.name}`)
  process.exit(0)
}

const file = args.find((a) => !a.startsWith('--'))
if (!file) {
  console.error('\n  Give a migration file, or --list.\n')
  process.exit(1)
}

await run(readFileSync(file, 'utf8'))
console.log(`\n  Applied ${file}\n`)
