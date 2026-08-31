/**
 * The verification queue: who is waiting, and answering them.
 *
 *   node scripts/verifications.mjs
 *   node scripts/verifications.mjs --approve <id> --note "Emirates ID seen in person, name and photo match."
 *   node scripts/verifications.mjs --reject  <id> --reason "The photo page was cut off. Send one showing all four corners."
 *
 * Deciding who somebody is cannot be an action available in a browser or on a
 * phone, so both the queue and the decision are service-role only and live
 * here. scripts/verify-identity.mjs still exists for verifying somebody who
 * never went through the queue, which is how the first few accounts were done.
 *
 * A refusal needs a real reason, in at least ten characters, enforced twice in
 * the database. The person sees exactly what you write, so write it to them
 * rather than about them: it is the only thing they have to act on.
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
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
    if (!out[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      process.exit(1)
    }
  }
  return out
}

const cfg = env()

/**
 * Straight PostgREST rather than the SDK, so the call is visibly the same one
 * the app would make if it were allowed to, with the one key it is not.
 */
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
    console.error(`\n  Refused: ${data?.message ?? `HTTP ${response.status}`}\n`)
    process.exit(1)
  }
  return data
}

const args = process.argv.slice(2)
const flag = (name) => {
  const at = args.indexOf(name)
  return at === -1 ? null : args[at + 1]
}

const KINDS = {
  emirates_id: 'Emirates ID',
  passport: 'Passport',
  trade_licence: 'Trade licence',
}

function ago(iso) {
  const hours = (Date.now() - new Date(iso).getTime()) / 3600000
  if (hours < 1) return 'just now'
  if (hours < 48) return `${Math.round(hours)}h`
  return `${Math.round(hours / 24)}d`
}

async function queue() {
  const rows = await rpc('verification_queue')
  if (!rows.length) {
    console.log('\n  Nobody is waiting.\n')
    return rows
  }
  console.log(`\n  ${rows.length} waiting, oldest first\n`)
  for (const r of rows) {
    console.log(`  ${r.request_id}`)
    console.log(`    ${r.legal_name}   (account: ${r.full_name} <${r.email}>)`)
    console.log(`    ${KINDS[r.document_kind] ?? r.document_kind}   waiting ${ago(r.waiting_since)}`)
    if (r.how) console.log(`    "${r.how}"`)
    // Worth seeing side by side. The name on the document and the name typed
    // at signup disagreeing is not suspicious on its own, and is exactly the
    // thing a queue should put in front of you rather than hide.
    if (r.legal_name.trim().toLowerCase() !== r.full_name.trim().toLowerCase()) {
      console.log(`    note: the name given differs from the one on the account`)
    }
    console.log('')
  }
  return rows
}

const approve = flag('--approve')
const reject = flag('--reject')

if (approve) {
  const note = flag('--note')
  if (!note || note.trim().length < 10) {
    console.error('\n  --note is required, and has to say what you actually looked at.\n')
    process.exit(1)
  }
  const [result] = await rpc('decide_verification', {
    p_request_id: approve,
    p_approve: true,
    p_note: note,
  })
  console.log(`\n  ${result.who} is verified.\n`)
  await queue()
} else if (reject) {
  const reason = flag('--reason')
  if (!reason || reason.trim().length < 10) {
    console.error('\n  --reason is required. They see it, and it is all they have to act on.\n')
    process.exit(1)
  }
  const [result] = await rpc('decide_verification', {
    p_request_id: reject,
    p_approve: false,
    p_note: reason,
  })
  console.log(`\n  ${result.who} was refused, and can ask again.\n`)
  await queue()
} else {
  await queue()
}
