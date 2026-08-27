/**
 * Signs up for real, through the public API, so you can watch for the email.
 *
 *   node scripts/test-signup-email.mjs you+trustiq1@gmail.com
 *   node scripts/test-signup-email.mjs you+trustiq1@gmail.com --clean
 *
 * Every other script here creates accounts with the service role and
 * email_confirm: true, which skips the mail entirely. That is the right thing
 * for a test fixture and useless for testing the one path a real person takes.
 * This one goes through auth.signUp with the publishable key, exactly as the
 * app does.
 *
 * Use a plus-address on a mailbox you can open. Gmail and most providers
 * deliver you+anything@ to you, so you can run this repeatedly without
 * burning addresses.
 *
 * --clean removes the account afterwards, so the same address can be used
 * again. Without it the address is taken and a second run reports that.
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
  for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

async function main() {
  const cfg = env()
  const email = process.argv.slice(2).find((a) => !a.startsWith('--'))
  const clean = process.argv.includes('--clean')

  if (!email) {
    console.error('\n  Give an address you can actually open.\n')
    return 1
  }

  // The publishable key, deliberately. The service role would create the
  // account without ever asking the mail server to do anything.
  const app = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  console.log(`\n  Signing up ${email} the way the app does.\n`)

  const { data, error } = await app.auth.signUp({
    email,
    password: `Trustiq!${Math.random().toString(16).slice(2, 12)}`,
    options: { data: { full_name: 'Signup test' } },
  })

  if (error) {
    console.error(`  Refused: ${error.message}`)
    if (/rate|limit|too many/i.test(error.message)) {
      console.error(`
  That is the shared-sender limit: two emails an hour for the whole project
  until custom SMTP is configured. Wait, or fill the SMTP keys in .env and
  run scripts/configure-auth.mjs --apply.
`)
    }
    return 1
  }

  // A session means no confirmation was required. A user with no session
  // means Supabase accepted the signup and handed the message to the mail
  // server; whether it arrives is now between the provider and the inbox,
  // which is what you are about to check.
  const confirmed = Boolean(data.session)
  console.log(`  Accepted. user id ${data.user?.id}`)
  console.log(
    confirmed
      ? '  A session came back, so confirmation is NOT required. That is worth knowing: anyone can sign up with an address they do not own.'
      : '  No session, so confirmation is required and the email has been handed off.',
  )

  console.log(`
  Now go and look:

    - the inbox for ${email}, and the spam folder, which is where an
      unauthenticated sender usually lands
    - the link should point at the confirmation page, not at localhost
    - Supabase dashboard > Authentication > Logs, if nothing arrives at all
`)

  if (clean) {
    if (!cfg.SUPABASE_SERVICE_ROLE_KEY) {
      console.log('  --clean needs SUPABASE_SERVICE_ROLE_KEY. The account stays.\n')
      return 0
    }
    const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { error: gone } = await db.auth.admin.deleteUser(data.user.id)
    console.log(gone
      ? `  The account stays: ${gone.message}\n`
      : `  Account removed, so the address is free to test again.\n`)
  }

  return 0
}

process.exitCode = await main()
