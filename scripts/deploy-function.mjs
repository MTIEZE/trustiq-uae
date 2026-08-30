/**
 * Deploys one edge function, and the secrets it needs.
 *
 *   node scripts/deploy-function.mjs send-notifications
 *   node scripts/deploy-function.mjs send-notifications --secrets BREVO_API_KEY,SMTP_SENDER_EMAIL
 *   node scripts/deploy-function.mjs --list
 *
 * The Supabase CLI is not installed here and the project was never linked, so
 * this goes through the management API, the same way scripts/apply-migration.mjs
 * does. Single file per function: nothing deployed this way may import a local
 * module, because only the one file is uploaded.
 *
 * Secret values come from .env and are never printed. --list reports names and
 * nothing else, because a script that helpfully echoes what it configured is
 * how a key reaches a terminal log.
 */

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'

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
const base = `https://api.supabase.com/v1/projects/${ref}`
const auth = { Authorization: `Bearer ${cfg.SUPABASE_ACCESS_TOKEN}` }

async function api(path, init = {}) {
  const response = await fetch(base + path, {
    ...init,
    headers: { ...auth, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  })
  const text = await response.text()
  return { ok: response.ok, status: response.status, text }
}

async function main() {
  const args = process.argv.slice(2)

  if (args.includes('--list')) {
    const { ok, text } = await api('/functions')
    if (!ok) {
      console.error(`\n  Could not list the functions: ${text.slice(0, 200)}\n`)
      return 1
    }
    console.log('')
    for (const fn of JSON.parse(text)) {
      console.log(`  ${fn.slug.padEnd(22)} ${fn.status}  v${fn.version}  verify_jwt=${fn.verify_jwt}`)
    }
    console.log('')
    return 0
  }

  const slug = args.find((a) => !a.startsWith('--'))
  if (!slug) {
    console.error('\n  Give a function name, or --list.\n')
    return 1
  }

  const source = join('supabase', 'functions', slug, 'index.ts')
  if (!existsSync(source)) {
    console.error(`\n  No such function: ${source}\n`)
    return 1
  }

  const body = readFileSync(source, 'utf8')

  // Anything not fully qualified is resolved by deno.json's import map, and a
  // single-file deploy uploads neither the map nor what it points at. Checking
  // only for './' let '@trustiq/server' through, and replacing a working
  // resolve-dispute with one file took it off the air with a BOOT_ERROR until
  // it was redeployed with the CLI.
  const bare = [...body.matchAll(/(?:from|import)\s+['"]([^'"]+)['"]/g)]
    .map((m) => m[1])
    .filter((spec) => !/^(npm:|jsr:|node:|https?:|data:)/.test(spec))

  if (bare.length > 0) {
    console.error(`
  ${source} imports ${[...new Set(bare)].join(', ')}.

  Those resolve through supabase/functions/deno.json, and this uploads one
  file, so the deployed function would fail to start. Deploy it with the CLI
  instead, which bundles what it needs:

    npx supabase functions deploy ${slug} --project-ref <ref>
`)
    return 1
  }

  // Secrets first: a function that goes live before the values it reads
  // spends its first minutes answering "the service is not configured".
  const secretsArg = args.indexOf('--secrets')
  if (secretsArg !== -1 && args[secretsArg + 1]) {
    const names = args[secretsArg + 1].split(',').map((s) => s.trim()).filter(Boolean)
    const missing = names.filter((n) => !cfg[n])
    if (missing.length) {
      console.error(`\n  Not in .env: ${missing.join(', ')}\n`)
      return 1
    }
    const { ok, status, text } = await api('/secrets', {
      method: 'POST',
      body: JSON.stringify(names.map((name) => ({ name, value: cfg[name] }))),
    })
    if (!ok) {
      console.error(`\n  Could not set the secrets (HTTP ${status}): ${text.slice(0, 200)}\n`)
      return 1
    }
    console.log(`\n  Secrets set: ${names.join(', ')}`)
  }

  const existing = await api('/functions')
  const already = existing.ok
    ? JSON.parse(existing.text).some((f) => f.slug === slug)
    : false

  const payload = JSON.stringify({
    slug,
    name: slug,
    body,
    // The function checks the bearer against the service role key itself, but
    // the gateway rejecting anonymous traffic first costs nothing.
    verify_jwt: true,
  })

  const { ok, status, text } = already
    ? await api(`/functions/${slug}`, { method: 'PATCH', body: payload })
    : await api('/functions', { method: 'POST', body: payload })

  if (!ok) {
    console.error(`\n  Refused (HTTP ${status}): ${text.slice(0, 400)}\n`)
    return 1
  }

  const fn = JSON.parse(text)
  console.log(`\n  ${already ? 'Updated' : 'Created'} ${slug}: ${fn.status}, v${fn.version}\n`)
  return 0
}

process.exitCode = await main()
