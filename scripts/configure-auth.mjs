/**
 * Points the confirmation emails somewhere real, and sends them through a
 * mailbox that can actually deliver.
 *
 *   node scripts/configure-auth.mjs --show
 *   node scripts/configure-auth.mjs --apply
 *
 * The problem this fixes, measured on the live project rather than assumed:
 *
 *   site_url                       http://localhost:3000
 *   SMTP configured                false
 *   mailer_autoconfirm             false
 *   rate_limit_email_sent / hour   2
 *
 * Confirmation is required, the mail goes through Supabase's shared sender at
 * two messages an hour for the whole project, and the link in it points at the
 * machine of whoever set the project up. A real person could not create an
 * account, which put everything built so far behind a wall.
 *
 * Values come from .env and are never printed. --show reports presence for
 * anything secret, because a script that helpfully echoes what it configured
 * is how a key ends up in a terminal log.
 *
 * .env keys this reads:
 *
 *   TRUSTIQ_SITE_URL      where an email link lands. Defaults to the
 *                         confirmation page on the deployed site.
 *   TRUSTIQ_REDIRECT_URLS extra allowed redirect targets, comma separated.
 *   SMTP_HOST             from the provider (Resend, Brevo, Postmark...)
 *   SMTP_PORT             usually 587
 *   SMTP_USER
 *   SMTP_PASS
 *   SMTP_SENDER_EMAIL     the From address
 *   SMTP_SENDER_NAME      defaults to TrustIQ
 *
 * Without the SMTP keys it still fixes the URLs, which is the half that costs
 * nothing and blocks everything.
 */

import { readFileSync } from 'node:fs'

const DEFAULT_SITE = 'https://mtieze.github.io/trustiq-uae/confirmed.html'

// With a real sender behind it, the shared-sender limit is the wrong limit.
// Left alone when there is no SMTP: raising it would just mean burning through
// somebody else's quota faster.
const RATE_LIMIT_WITH_SMTP = 30

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

async function main() {
  const cfg = env()
  const ref = new URL(cfg.SUPABASE_URL).host.split('.')[0]
  const endpoint = `https://api.supabase.com/v1/projects/${ref}/config/auth`
  const auth = { Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}` }

  const read = async () => {
    const r = await fetch(endpoint, { headers: auth })
    if (!r.ok) {
      console.error(`\n  Could not read the auth config (HTTP ${r.status})\n`)
      process.exit(1)
    }
    return r.json()
  }

  // Never the whole response. It carries smtp_pass, and printing a config
  // dump is how a password ends up in a terminal log.
  const report = (a) => {
    const rows = [
      ['site_url', a.site_url],
      ['redirect allow list', a.uri_allow_list || '(empty)'],
      ['email confirmation required', !a.mailer_autoconfirm],
      ['custom SMTP', Boolean(a.smtp_host)],
      ['SMTP host', a.smtp_host || '(none)'],
      ['From address', a.smtp_admin_email || '(none)'],
      ['SMTP password set', Boolean(a.smtp_pass)],
      ['emails per hour', a.rate_limit_email_sent],
      ['signups open', !a.disable_signup],
    ]
    for (const [k, v] of rows) console.log('    ' + String(k).padEnd(30) + String(v))
  }

  if (process.argv.includes('--show')) {
    console.log('')
    report(await read())
    console.log('')
    return 0
  }

  if (!process.argv.includes('--apply')) {
    console.log('\n  Pass --show to read the current settings, or --apply to write them.\n')
    return 1
  }

  const site = cfg.TRUSTIQ_SITE_URL || DEFAULT_SITE
  const extra = (cfg.TRUSTIQ_REDIRECT_URLS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)

  // The allow list is what Supabase checks a redirect_to against. It was
  // empty, so even a correct link would have been refused.
  const allow = [...new Set([site, ...extra])].join(',')

  const body = { site_url: site, uri_allow_list: allow }

  const smtp = {
    host: cfg.SMTP_HOST,
    port: cfg.SMTP_PORT || '587',
    user: cfg.SMTP_USER,
    pass: cfg.SMTP_PASS,
    sender: cfg.SMTP_SENDER_EMAIL,
    name: cfg.SMTP_SENDER_NAME || 'TrustIQ',
  }

  const haveSmtp = Boolean(smtp.host && smtp.user && smtp.pass && smtp.sender)
  const partial = !haveSmtp && (smtp.host || smtp.user || smtp.pass || smtp.sender)

  if (partial) {
    // Half a mail configuration is worse than none: Supabase would accept it
    // and then fail to send, which looks to a new user exactly like an app
    // that ignored them.
    console.error(`
  The SMTP settings are incomplete. All four are needed:

    SMTP_HOST          ${smtp.host ? 'set' : 'MISSING'}
    SMTP_USER          ${smtp.user ? 'set' : 'MISSING'}
    SMTP_PASS          ${smtp.pass ? 'set' : 'MISSING'}
    SMTP_SENDER_EMAIL  ${smtp.sender ? 'set' : 'MISSING'}

  Nothing was changed.
`)
    return 1
  }

  if (haveSmtp) {
    Object.assign(body, {
      smtp_host: smtp.host,
      smtp_port: smtp.port,
      smtp_user: smtp.user,
      smtp_pass: smtp.pass,
      smtp_admin_email: smtp.sender,
      smtp_sender_name: smtp.name,
      rate_limit_email_sent: RATE_LIMIT_WITH_SMTP,
    })
  }

  const response = await fetch(endpoint, {
    method: 'PATCH',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })

  if (!response.ok) {
    console.error(`\n  Refused (HTTP ${response.status}): ${(await response.text()).slice(0, 400)}\n`)
    return 1
  }

  console.log(`\n  Applied. Reading it back:\n`)
  report(await read())

  if (!haveSmtp) {
    console.log(`
  Still on Supabase's shared sender, which is two emails an hour for the
  whole project and lands in spam often enough to matter. Fill the SMTP
  keys in .env and run this again.
`)
  }
  return 0
}

process.exitCode = await main()
