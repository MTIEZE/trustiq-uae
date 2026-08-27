/**
 * Takes two brand new, unverified accounts to an accepted contract.
 *
 *   node scripts/verify-manual-verification.mjs
 *   node scripts/verify-manual-verification.mjs --keep
 *
 * This is the journey that was impossible. Every account in the project until
 * now was seeded already verified, which meant the identity gate had never
 * been the thing standing in a real person's way. It was: a genuine signup
 * could draft a contract, send it, and then neither side could accept it,
 * with nothing anywhere able to change that.
 *
 * So the run starts unverified on purpose and expects to be refused, verifies
 * the two people the way a beta tester will actually be verified, and expects
 * the same call to go through. A run where the first accept succeeds is a run
 * that proved nothing.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `verif-${Math.random().toString(16).slice(2, 10)}`

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY']) {
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

const step = (t) => console.log(`\n${t}`)
const ok = (t) => console.log(`  ok  ${t}`)
let failures = 0

function must(label, { data, error }) {
  if (error) {
    console.error(`\nFAILED at: ${label}\n  ${error.message}\n`)
    process.exit(1)
  }
  return data
}

function expectRefused(label, { error }, contains) {
  if (!error) {
    console.error(`  FAIL  ${label} — it was allowed`)
    failures += 1
    return
  }
  if (contains && !error.message.includes(contains)) {
    console.error(`  FAIL  ${label} — refused, but for the wrong reason: ${error.message}`)
    failures += 1
    return
  }
  ok(`${label}\n        refused: ${error.message}`)
}

async function actAs(email, password) {
  const client = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error } = await client.auth.signInWithPassword({ email, password })
  if (error) {
    console.error(`\nCould not sign in as ${email}: ${error.message}\n`)
    process.exit(1)
  }
  return client
}

/* ------------------------------------------------------------------ */

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const buyerEmail = `buyer.${RUN}@example.test`
const sellerEmail = `seller.${RUN}@example.test`

step('Two accounts, neither verified')

const buyer = must('creating the buyer',
  await db.auth.admin.createUser({ email: buyerEmail, password, email_confirm: true })).user
const seller = must('creating the seller',
  await db.auth.admin.createUser({ email: sellerEmail, password, email_confirm: true })).user

// No identity columns. This is the difference from the seed script, and it is
// the entire point of the run.
must('creating profiles', await db.from('profiles').insert([
  { id: buyer.id, full_name: 'Layla Haddad', email: buyerEmail },
  { id: seller.id, full_name: 'Omar Fakhoury', email: sellerEmail },
]))
ok('both profiles exist, both unverified')

step('Drafting and sending a contract, which needs no verification')

const asBuyer = await actAs(buyerEmail, password)
const asSeller = await actAs(sellerEmail, password)

const contract = must('creating the contract', await asBuyer
  .from('transactions')
  .insert({
    buyer_id: buyer.id,
    seller_id: seller.id,
    description: `Website copy for a clinic [${RUN}]`,
    terms: 'Six pages of copy within ten days. One round of revision.',
    total_amount_fils: 120000,
    created_by: buyer.id,
  })
  .select('id, state')
  .single())
ok(`contract ${contract.id} created as ${contract.state}`)

must('submit', await asBuyer.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'submit',
}))
ok('the buyer sent it, still unverified')

step('The gate, with nobody verified')

expectRefused('the seller cannot accept',
  await asSeller.rpc('apply_transaction_event', {
    p_transaction_id: contract.id, p_event: 'accept',
  }),
  'verified identity')

step('The seller cannot let themselves through')

expectRefused('their own session cannot call the verification function',
  await asSeller.rpc('record_manual_verification', {
    p_user_id: seller.id, p_note: 'I have checked my own documents, they are fine',
  }),
  'permission denied')

expectRefused('nor write the column directly',
  await asSeller.from('profiles')
    .update({ identity_verified_at: new Date().toISOString() })
    .eq('id', seller.id)
    .select('id')
    .single())

step('A person at TrustIQ checks their documents')

for (const [who, id] of [['buyer', buyer.id], ['seller', seller.id]]) {
  const at = must(`verifying the ${who}`, await db.rpc('record_manual_verification', {
    p_user_id: id,
    p_note: `Emirates ID shown over video call, name and photo match the account (${RUN})`,
  }))
  ok(`${who} verified at ${at}`)
}

const stamped = must('reading the profiles back', await db
  .from('profiles')
  .select('email, identity_provider, identity_verified_at')
  .in('id', [buyer.id, seller.id]))

for (const p of stamped) {
  if (p.identity_provider !== 'manual_review') {
    console.error(`  FAIL  ${p.email} is stamped ${p.identity_provider}, not manual_review`)
    failures += 1
  }
}
ok('both are stamped manual_review, not uae_pass')

step('The same call, now')

must('accept', await asSeller.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'accept',
}))

const after = must('reading the contract back', await asSeller
  .from('transactions').select('state').eq('id', contract.id).single())

if (after.state !== 'active') {
  console.error(`  FAIL  the contract is ${after.state}, not active`)
  failures += 1
} else {
  ok('the seller accepted and the contract is active')
}

/* ------------------------------------------------------------------ */

if (!process.argv.includes('--keep')) {
  step('Clearing up')
  // The contract may refuse to go: transitions are append-only and the history
  // is meant to outlast the parties. Say so rather than reporting a clean that
  // did not happen.
  const { error: txnError } = await db.from('transactions').delete().eq('id', contract.id)
  console.log(txnError
    ? `  contract ${contract.id} stays: ${txnError.message}`
    : `  contract ${contract.id} removed`)

  // GoTrue reports this as "Database error deleting user", which says nothing.
  // Nine foreign keys reference a profile with ON DELETE RESTRICT, and these
  // two accounts trip several of them: they are parties to a contract, and
  // they each have an identity check on record. Both are deliberate. Removing
  // a person would take the other party's contract history with them, and the
  // record of who vouched for an identity is the thing that makes the
  // verification worth anything. It is also the open legal question about the
  // right to erasure, which the append-only evidence and event tables raise in
  // the same way.
  for (const [who, id] of [['buyer', buyer.id], ['seller', seller.id]]) {
    const { error } = await db.auth.admin.deleteUser(id)
    console.log(error
      ? `  ${who} account stays: ${error.message} (they are on a contract, and on the identity record)`
      : `  ${who} account removed`)
  }

  console.log([
    '',
    '  This run leaves data behind on purpose. Nothing here can be unwritten:',
    '  the contract history, the identity checks and the accounts they belong to',
    '  all outlast the test that made them.',
  ].join('\n'))
}

console.log(failures === 0
  ? '\nManual verification is the thing that opens the gate, and only the server can do it.\n'
  : `\n${failures} check(s) failed.\n`)
process.exit(failures === 0 ? 0 : 1)
