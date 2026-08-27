/**
 * What can somebody do holding only the key that ships inside the app?
 *
 *   node scripts/probe-anon-reach.mjs
 *
 * Kept as a script rather than a one-off because the answer changes every time
 * a function is added: Supabase grants EXECUTE on new functions in `public` to
 * anon automatically, so the safe state is the one that has to be maintained.
 *
 * Nothing here writes. The user ids are deliberately ones that do not exist,
 * so a function that lets the call through fails on the missing row and says
 * so, which is how a reachable function is told apart from a refused one.
 */

import { readFileSync } from 'node:fs'

const cfg = {}
for (const line of readFileSync('.env', 'utf8').split('\n')) {
  const t = line.trim()
  if (!t || t.startsWith('#')) continue
  const at = t.indexOf('=')
  if (at !== -1) cfg[t.slice(0, at).trim()] = t.slice(at + 1).trim()
}

const NOWHERE = '99999999-9999-9999-9999-999999999999'
const key = cfg.SUPABASE_ANON_KEY
const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }

const calls = [
  ['record_manual_verification', { p_user_id: NOWHERE, p_note: 'probe, no such profile' }],
  ['revoke_verification', { p_user_id: NOWHERE, p_note: 'probe, no such profile' }],
  ['issue_ai_proposal', { p_dispute_id: NOWHERE, p_decision: 'split', p_summary: 'probe',
    p_disputed_amount_fils: 2, p_seller_amount_fils: 1, p_buyer_amount_fils: 1,
    p_confidence: 0.5, p_model_id: 'probe', p_issued_at: null, p_findings: [] }],
  ['issue_human_resolution', { p_dispute_id: NOWHERE, p_decision: 'split', p_summary: 'probe',
    p_seller_amount_fils: 1, p_buyer_amount_fils: 1 }],
  ['claim_dispute', { p_dispute_id: NOWHERE }],
  ['find_counterparty', { p_email: 'nobody@example.test' }],
  ['apply_transaction_event', { p_transaction_id: NOWHERE, p_event: 'submit' }],
]

let reachable = 0
console.log('\n  Holding only the publishable key, with no session:\n')

for (const [fn, body] of calls) {
  const r = await fetch(`${cfg.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers, body: JSON.stringify(body),
  })
  const text = await r.text()
  // 42501 is Postgres refusing EXECUTE, which is the grant doing its job, and
  // 404 is PostgREST not exposing the function to this role at all. Anything
  // else means the call got inside the function body, which is the thing being
  // probed for: the hole this script exists to catch let an anonymous caller
  // reach a check that was only ever written to stop signed-in users.
  const blocked = r.status === 404 || text.includes('"42501"')
  if (!blocked) reachable += 1
  console.log(`    ${blocked ? 'refused ' : 'REACHED '} ${fn.padEnd(28)} HTTP ${r.status}  ${text.slice(0, 110)}`)
}

console.log(
  reachable === 0
    ? '\n  Nothing routed. The key opens no function.\n'
    : `\n  ${reachable} function(s) still routed with the app key.\n`,
)
process.exit(reachable === 0 ? 0 : 1)
