/**
 * Walks the whole verification journey against the live project.
 *
 *   node scripts/verify-verification.mjs
 *
 * The schema tests prove the rules on a disposable Postgres and the widget
 * tests prove the screens against a double. Neither walks the path a real phone
 * takes: PostgREST, the publishable key, a real session. This does, and it goes
 * all the way round, including the part that did not exist before today —
 * asking, being refused with a reason, and asking again.
 *
 * The throwaway account is deleted at the end.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `verify-${Math.random().toString(16).slice(2, 10)}`

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
const admin = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const step = (t) => console.log(`\n${t}`)
const ok = (t) => console.log(`  ok  ${t}`)
let failures = 0

function check(label, condition, detail) {
  if (condition) return ok(label)
  console.error(`  FAIL  ${label}${detail ? ` (${detail})` : ''}`)
  failures += 1
}

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const email = `journey.${RUN}@example.test`

step('An account that has never asked')

const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
if (created.error) {
  console.error(`\n  could not create the account: ${created.error.message}\n`)
  process.exit(1)
}
const userId = created.data.user.id
await admin.from('profiles').insert({ id: userId, full_name: 'Journey Walker', email })

// From here, only what the app itself holds.
const app = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const signIn = await app.auth.signInWithPassword({ email, password })
if (signIn.error) {
  console.error(`\n  could not sign in: ${signIn.error.message}\n`)
  process.exit(1)
}
ok('signed in with the key that ships in the app')

const standing = async () => {
  const { data, error } = await app.rpc('my_verification')
  if (error) {
    console.error(`\n  my_verification failed: ${error.message}\n`)
    process.exit(1)
  }
  return Array.isArray(data) ? data[0] : data
}

{
  const s = await standing()
  // The state that did not exist. "Never asked" used to be indistinguishable
  // from "was refused", and the screen could only ever explain.
  check('is told "none" rather than handed an empty answer', s?.standing === 'none',
    JSON.stringify(s))
}

step('Asking')

{
  const { error } = await app.rpc('request_verification', {
    p_legal_name: 'Journey Walker Al Suwaidi',
    p_document_kind: 'emirates_id',
    p_how: 'Happy to come to the office in Sharjah.',
  })
  check('the request is accepted', !error, error?.message)
}

{
  const s = await standing()
  check('and they are told they are waiting', s?.standing === 'pending')
  check('with the name they gave, not the one on the account',
    s?.legal_name === 'Journey Walker Al Suwaidi', s?.legal_name)
}

{
  const { error } = await app.rpc('request_verification', {
    p_legal_name: 'Journey Walker Al Suwaidi',
    p_document_kind: 'passport',
  })
  check('asking twice is refused, so nobody is in the queue twice', Boolean(error))
}

step('The queue, which the app cannot see')

{
  const { error } = await app.rpc('verification_queue')
  check('a signed-in person cannot read the queue', Boolean(error),
    error ? undefined : 'it answered')
}

{
  const { error } = await app.rpc('decide_verification', {
    p_request_id: '00000000-0000-0000-0000-000000000000',
    p_approve: true,
    p_note: 'I would like to verify myself, please.',
  })
  check('nor decide their own verification', Boolean(error))
}

const queue = await admin.rpc('verification_queue')
const mine = (queue.data ?? []).find((r) => r.user_id === userId)
check('the operator sees the request waiting', Boolean(mine))
check('with the address to answer at', mine?.email === email)

step('Refused, with something to act on')

{
  const { error } = await admin.rpc('decide_verification', {
    p_request_id: mine.request_id,
    p_approve: false,
    p_note: 'The photo page was cut off. Send one showing all four corners.',
  })
  check('the refusal is recorded', !error, error?.message)
}

{
  const s = await standing()
  check('the person is told they were refused', s?.standing === 'rejected')
  check('and told why, which is the whole point of recording it',
    (s?.reason ?? '').startsWith('The photo page'), s?.reason)
}

{
  const { error } = await admin.rpc('decide_verification', {
    p_request_id: mine.request_id,
    p_approve: false,
    p_note: 'Changed my mind.',
  })
  check('an answered request cannot be answered twice', Boolean(error))
}

step('Asking again, which is the reason a refusal is not a dead end')

{
  const { error } = await app.rpc('request_verification', {
    p_legal_name: 'Journey Walker Al Suwaidi',
    p_document_kind: 'emirates_id',
    p_how: 'Full page this time.',
  })
  check('a refused person can ask again', !error, error?.message)
}

const again = await admin.rpc('verification_queue')
const second = (again.data ?? []).find((r) => r.user_id === userId)

{
  const { error } = await admin.rpc('decide_verification', {
    p_request_id: second.request_id,
    p_approve: true,
    p_note: 'Emirates ID seen in person at the Sharjah office, name and photo match.',
  })
  check('and be verified', !error, error?.message)
}

{
  const s = await standing()
  check('the person is told they are verified', s?.standing === 'verified')
}

{
  const { data } = await admin
    .from('profiles')
    .select('identity_verified_at, identity_provider')
    .eq('id', userId)
    .single()
  check('the profile is stamped', data?.identity_verified_at !== null)
  check('as a manual review, never as UAE Pass',
    data?.identity_provider === 'manual_review', data?.identity_provider)
}

{
  const { error } = await app.rpc('request_verification', {
    p_legal_name: 'Journey Walker Al Suwaidi',
    p_document_kind: 'passport',
  })
  check('and cannot join the queue again', Boolean(error))
}

{
  const left = await admin.rpc('verification_queue')
  check('nothing of theirs is left waiting',
    !(left.data ?? []).some((r) => r.user_id === userId))
}

step('Clearing up')
await admin.auth.admin.deleteUser(userId)
ok('throwaway account removed')

if (failures) {
  console.error(`\n  ${failures} check${failures === 1 ? '' : 's'} failed\n`)
  process.exit(1)
}
console.log('\n  Somebody can ask, be told no with a reason, fix it, and be verified.\n')
