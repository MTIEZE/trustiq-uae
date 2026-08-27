/**
 * Marks a beta tester's identity verified, after a person looked at their
 * documents.
 *
 *   node scripts/verify-identity.mjs sara@example.ae --note "Emirates ID shown over video call, name and photo match the account"
 *   node scripts/verify-identity.mjs sara@example.ae --revoke --note "ID turned out to belong to somebody else"
 *   node scripts/verify-identity.mjs --list
 *   node scripts/verify-identity.mjs sara@example.ae --history
 *
 * Why this exists: the identity gate refuses to activate a contract until both
 * parties are verified, and until UAE Pass is connected nothing can verify
 * anybody. Without this, a real person can sign up and then get no further.
 *
 * Why it is a script and not a screen: verifying somebody is an administrative
 * act. It needs the service role, it is recorded permanently, and it should
 * not be possible from a phone. Same shape as scripts/add-reviewer.mjs.
 *
 * The note is not decoration. It is written into an append-only table and it
 * is the only thing that will answer "on what basis?" if a verification is
 * ever questioned. Write what you actually looked at.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const MIN_NOTE = 10

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

function when(iso) {
  return iso ? new Date(iso).toISOString().replace('T', ' ').slice(0, 16) : ''
}

/* ------------------------------------------------------------------ *
 * The work runs inside main() so every path can return instead of
 * calling process.exit(). Exiting while the Supabase client still holds
 * a socket makes libuv print "Assertion failed: !(handle->flags &
 * UV_HANDLE_CLOSING)" after the last line of output, which reads like a
 * crash at the end of a run that went perfectly.
 * ------------------------------------------------------------------ */

async function main() {
  const cfg = env()
  const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const args = process.argv.slice(2)
  const listing = args.includes('--list')
  const revoking = args.includes('--revoke')
  const history = args.includes('--history')

  // The note is quoted text and may well contain an @ ("checked @ the
  // office"), so skip whatever follows --note rather than sniffing every
  // argument for an at sign.
  const noteAt = args.indexOf('--note')
  // -1 + 1 is 0, which would skip the first argument, which is where the email
  // usually is. With no --note there is nothing to skip at all.
  const skip = noteAt === -1 ? -1 : noteAt + 1
  const email = args.find((a, i) => i !== skip && !a.startsWith('--') && a.includes('@'))
  const note = noteAt === -1 ? null : (args[noteAt + 1] ?? '')

  if (listing) {
    const { data, error } = await db
      .from('profiles')
      .select('email, full_name, identity_provider, identity_verified_at')
      .not('identity_verified_at', 'is', null)
      .order('identity_verified_at', { ascending: false })

    if (error) {
      console.error(`\n  Could not read the profiles: ${error.message}\n`)
      return 1
    }
    if (data.length === 0) {
      console.log('\n  Nobody is verified yet.\n')
      return 0
    }
    console.log(`\n  ${data.length} verified:\n`)
    for (const p of data) {
      console.log(
        `    ${when(p.identity_verified_at)}  ${(p.identity_provider ?? '?').padEnd(13)}  ` +
        `${p.email}  (${p.full_name})`,
      )
    }
    console.log('')
    return 0
  }

  if (!email) {
    console.error('\n  Give an email address.\n')
    return 1
  }

  const { data: users, error: listError } = await db.auth.admin.listUsers({ perPage: 1000 })
  if (listError) {
    console.error(`\n  Could not read the accounts: ${listError.message}\n`)
    return 1
  }

  const user = users.users.find((u) => u.email?.toLowerCase() === email.toLowerCase())
  if (!user) {
    console.error(`\n  Nobody holds ${email}. They need an account first.\n`)
    return 1
  }

  if (history) {
    // app.identity_checks is outside the schema PostgREST exposes,
    // deliberately: the record of who was verified and why is not an API
    // surface. Reading it needs SQL, which is what the management token is for.
    const sql =
      `select checked_at, outcome, note from app.identity_checks\n` +
      `     where user_id = '${user.id}' order by checked_at desc`

    if (!cfg.SUPABASE_ACCESS_TOKEN) {
      console.log(`\n  SUPABASE_ACCESS_TOKEN is not set. Paste this into the SQL editor:\n\n    ${sql};\n`)
      return 0
    }

    const ref = new URL(cfg.SUPABASE_URL).host.split('.')[0]
    const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: sql }),
    })
    if (!response.ok) {
      console.error(`\n  Refused (HTTP ${response.status}): ${(await response.text()).slice(0, 300)}\n`)
      return 1
    }

    const rows = await response.json()
    if (rows.length === 0) {
      console.log(`\n  No identity check has ever been recorded for ${email}.\n`)
      return 0
    }
    console.log(`\n  ${email}\n`)
    for (const r of rows) console.log(`    ${when(r.checked_at)}  ${r.outcome.padEnd(8)}  ${r.note}`)
    console.log('')
    return 0
  }

  if (note === null || note.trim().length < MIN_NOTE) {
    console.error(`
  --note is required, and has to say something.

  It goes into an append-only record and it is the only answer there will ever
  be to "on what basis was this person verified?". Write what you looked at:

    --note "Emirates ID shown over video call, name and photo match the account"
`)
    return 1
  }

  const { data: at, error } = await db.rpc(
    revoking ? 'revoke_verification' : 'record_manual_verification',
    { p_user_id: user.id, p_note: note },
  )

  if (error) {
    console.error(`\n  Refused: ${error.message}\n`)
    return 1
  }

  console.log(revoking
    ? `\n  ${email} is no longer verified. The record of both decisions stays.\n`
    : `\n  ${email} is verified as of ${when(at)}, stamped manual_review.\n`)
  return 0
}

process.exitCode = await main()
