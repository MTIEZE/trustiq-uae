/**
 * The things that happen because time passed.
 *
 *   node scripts/run-schedule.mjs
 *   node scripts/run-schedule.mjs --dry
 *
 * The database has neither pg_cron nor pg_net, so nothing inside it can act on
 * a date going by. Three functions wait to be called, and this is the caller:
 *
 *   expire_overdue_contracts   a deadline that passed with no answer
 *   renew_due_contracts        a period that ran out under an automatic policy
 *   write_deadline_notices     warning both parties before either happens
 *
 * Order matters. Expiring first means a contract that timed out is not also
 * warned about; writing notices last means a renewal that just happened does
 * not also get a "period ending" notice for the period it left behind.
 *
 * Every one of them is safe to run twice. That is deliberate rather than
 * lucky: a scheduler that skips a day should catch up on the next run without
 * anybody thinking about it, and one that runs twice should do nothing the
 * second time.
 */

import { readFileSync } from 'node:fs'

function env() {
  const out = {}
  try {
    for (const line of readFileSync('.env', 'utf8').split('\n')) {
      const t = line.trim()
      if (!t || t.startsWith('#')) continue
      const at = t.indexOf('=')
      if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
    }
  } catch {
    // On a runner there is no .env; the values arrive as environment variables.
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
    out[k] ??= process.env[k]
    if (!out[k]) {
      console.error(`\n  ${k} is not set\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()
const dry = process.argv.includes('--dry')

async function rpc(name, body) {
  const response = await fetch(`${cfg.SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: cfg.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${cfg.SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body ?? {}),
  })
  const data = await response.json().catch(() => null)
  if (!response.ok) {
    // Reported and rethrown rather than swallowed. A scheduler that fails
    // quietly is a scheduler nobody notices has stopped.
    throw new Error(`${name}: ${data?.message ?? `HTTP ${response.status}`}`)
  }
  return data
}

if (dry) {
  console.log('\n  --dry: nothing is called. The three steps would be:\n')
  console.log('    expire_overdue_contracts')
  console.log('    renew_due_contracts')
  console.log('    write_deadline_notices\n')
  process.exit(0)
}

let failed = false

try {
  const expired = await rpc('expire_overdue_contracts')
  console.log(`  expired   ${expired.length}`)
  for (const row of expired) {
    console.log(`            ${row.transaction_id}  deadline was ${row.deadline}`)
  }
} catch (e) {
  console.error(`  FAILED    ${e.message}`)
  failed = true
}

try {
  const renewed = await rpc('renew_due_contracts')
  console.log(`  renewed   ${renewed.length}`)
  for (const row of renewed) {
    console.log(`            ${row.transaction_id}  ${row.from_ends_on} -> ${row.to_ends_on}`)
  }
} catch (e) {
  console.error(`  FAILED    ${e.message}`)
  failed = true
}

try {
  const notices = await rpc('write_deadline_notices')
  for (const row of notices) {
    console.log(`  notices   ${row.event.padEnd(22)} ${row.written}`)
  }
} catch (e) {
  console.error(`  FAILED    ${e.message}`)
  failed = true
}

if (failed) process.exit(1)
