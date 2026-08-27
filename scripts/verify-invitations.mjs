/**
 * Takes an invitation from a code to a live contract, through the real API.
 *
 *   node scripts/verify-invitations.mjs
 *
 * The schema tests already prove the rules against a real Postgres. What they
 * cannot prove is the surface: invite_counterparty returns a composite type,
 * and how PostgREST shapes that on the way out is the sort of thing that is
 * fine in psql and wrong in the app. So this drives it the way the phone does,
 * with a signed-in session and the publishable key.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `inv-${Math.random().toString(16).slice(2, 10)}`

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
    console.error(`  FAIL  ${label} — refused for the wrong reason: ${error.message}`)
    failures += 1
    return
  }
  ok(`${label}\n        refused: ${error.message}`)
}

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
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

async function makeAccount(email, password, name, { verified }) {
  const user = must(`creating ${email}`,
    await db.auth.admin.createUser({ email, password, email_confirm: true })).user
  must(`profile for ${email}`,
    await db.from('profiles').insert({ id: user.id, full_name: name, email }))
  if (verified) {
    must(`verifying ${email}`, await db.rpc('record_manual_verification', {
      p_user_id: user.id,
      p_note: `Verified for the invitation check (${RUN})`,
    }))
  }
  return user
}

/* ------------------------------------------------------------------ */

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const inviterEmail = `inviter.${RUN}@example.test`
const inviteeEmail = `invitee.${RUN}@example.test`
const strangerEmail = `stranger.${RUN}@example.test`

step('One person with an account, and one address with none')

const inviter = await makeAccount(inviterEmail, password, 'Rania Kassem', { verified: true })
await makeAccount(strangerEmail, password, 'Stranger', { verified: false })
ok(`${inviterEmail} exists; nobody holds ${inviteeEmail}`)

step('Addressing a contract to an address with no account')

const asInviter = await actAs(inviterEmail, password)

expectRefused('the lookup still says nobody holds it',
  await asInviter.rpc('find_counterparty', { p_email: inviteeEmail }).then(
    (r) => (r.data == null && !r.error
      ? { error: { message: 'find_counterparty returned null' } }
      : r)),
  'returned null')

const invitation = must('creating the invitation', await asInviter.rpc('invite_counterparty', {
  p_email: inviteeEmail,
  p_invitee_is: 'seller',
  p_description: `Arabic copy for a landing page [${RUN}]`,
  p_terms: 'Six sections within five days. One round of revision.',
  p_total_amount_fils: 75000,
}))

// The shape is the point of running this at all.
check('the composite comes back as an object with a code',
  invitation && typeof invitation === 'object' && typeof invitation.code === 'string',
  JSON.stringify(invitation).slice(0, 120))

check('the code is readable down a phone',
  /^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(invitation.code ?? ''), invitation.code)

check('no contract exists yet', invitation.transaction_id === null)

const listed = must('listing what was sent', await asInviter.rpc('my_invitations', {}))
check('the inviter sees it in their list',
  Array.isArray(listed) && listed.some((i) => i.code === invitation.code),
  `${listed?.length} row(s)`)

step('The code alone is not enough')

const asStranger = await actAs(strangerEmail, password)
expectRefused('somebody else holding the code cannot use it',
  await asStranger.rpc('claim_invitation', { p_code: invitation.code }),
  'no invitation for you')

expectRefused('a made-up code gets the same answer',
  await asStranger.rpc('claim_invitation', { p_code: 'ZZZZ-ZZZZ' }),
  'no invitation for you')

step('The person it was for signs up')

await makeAccount(inviteeEmail, password, 'Yousef Nasser', { verified: true })
const asInvitee = await actAs(inviteeEmail, password)

const contractId = must('claiming', await asInvitee.rpc('claim_invitation', {
  p_code: invitation.code,
}))

const contract = must('reading the contract back', await asInvitee
  .from('transactions')
  .select('id, state, buyer_id, seller_id, created_by, total_amount_fils')
  .eq('id', contractId)
  .single())

check('it arrives already sent, not as a draft',
  contract.state === 'pending_acceptance', contract.state)
check('the invitee is on the side the invitation named',
  contract.seller_id !== inviter.id && contract.buyer_id === inviter.id)
check('the inviter is recorded as its author', contract.created_by === inviter.id)
check('the amount survived intact', Number(contract.total_amount_fils) === 75000)

expectRefused('the code will not work twice',
  await asInvitee.rpc('claim_invitation', { p_code: invitation.code }),
  'already been used')

step('And the contract is now an ordinary contract')

must('accepting it', await asInvitee.rpc('apply_transaction_event', {
  p_transaction_id: contractId,
  p_event: 'accept',
}))

const after = must('reading it again', await asInvitee
  .from('transactions').select('state').eq('id', contractId).single())
check('both parties being verified, it activates like any other',
  after.state === 'active', after.state)

console.log(failures === 0
  ? '\nA contract can now start with somebody who had never heard of TrustIQ.\n'
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
