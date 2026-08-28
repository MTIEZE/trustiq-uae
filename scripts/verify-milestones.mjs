/**
 * Walks a two stage contract from drafted to completed, one stage at a time.
 *
 *   node scripts/verify-milestones.mjs
 *
 * The schema tests prove the rules against a real Postgres. This proves the
 * surface: three functions called over PostgREST with real sessions, and the
 * milestones table readable by the parties, which is how the app reaches all
 * of it. Until now nothing outside the demo data had ever loaded a milestone.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const RUN = `stage-${Math.random().toString(16).slice(2, 10)}`

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

async function makeAccount(email, name) {
  const user = must(`creating ${email}`,
    await db.auth.admin.createUser({ email, password, email_confirm: true })).user
  must(`profile for ${email}`,
    await db.from('profiles').insert({ id: user.id, full_name: name, email }))
  must(`verifying ${email}`, await db.rpc('record_manual_verification', {
    p_user_id: user.id, p_note: `Verified for the milestone check (${RUN})`,
  }))
  return user
}

const stateOf = async (client, id) =>
  (await client.from('transactions').select('state').eq('id', id).single()).data?.state

/* ------------------------------------------------------------------ */

const password = `Trustiq!${Math.random().toString(16).slice(2, 12)}`
const buyerEmail = `client.${RUN}@example.test`
const sellerEmail = `freelance.${RUN}@example.test`

step('A client and a freelancer')

const buyer = await makeAccount(buyerEmail, 'Hala Mansour')
const seller = await makeAccount(sellerEmail, 'Tarek Aziz')
const asBuyer = await actAs(buyerEmail, password)
const asSeller = await actAs(sellerEmail, password)

step('A contract in two stages, written by the client')

const contract = must('creating the contract', await asBuyer
  .from('transactions')
  .insert({
    buyer_id: buyer.id,
    seller_id: seller.id,
    description: `Booking site [${RUN}]`,
    terms: 'Design first, then the build.',
    total_amount_fils: 500000,
    created_by: buyer.id,
  })
  .select('id')
  .single())

const stages = must('adding the stages', await asBuyer
  .from('milestones')
  .insert([
    { transaction_id: contract.id, position: 0, title: 'Design', amount_fils: 200000 },
    { transaction_id: contract.id, position: 1, title: 'Build', amount_fils: 300000 },
  ])
  .select('id, position')
  .order('position'))
ok(`two stages on contract ${contract.id}`)

expectRefused('the stages cannot add up to more than the contract',
  await asBuyer.from('milestones').insert({
    transaction_id: contract.id, position: 2, title: 'Too much', amount_fils: 1,
  }))

must('submit', await asBuyer.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'submit',
}))
must('accept', await asSeller.rpc('apply_transaction_event', {
  p_transaction_id: contract.id, p_event: 'accept',
}))

expectRefused('and no stage can be added once it is live',
  await asBuyer.from('milestones').insert({
    transaction_id: contract.id, position: 2, title: 'Snuck in', amount_fils: 1,
  }))

const [design, build] = stages

step('The freelancer delivers the first stage')

expectRefused('the client cannot deliver it for them',
  await asBuyer.rpc('deliver_milestone', { p_milestone_id: design.id }),
  'only the seller')

must('deliver', await asSeller.rpc('deliver_milestone', { p_milestone_id: design.id }))
check('the contract stays active, because one stage of two is not the work',
  (await stateOf(asSeller, contract.id)) === 'active')

step('The client sends it back, then accepts the second attempt')

must('send back', await asBuyer.rpc('request_milestone_revision', { p_milestone_id: design.id }))
must('deliver again', await asSeller.rpc('deliver_milestone', { p_milestone_id: design.id }))
must('accept', await asBuyer.rpc('accept_milestone', { p_milestone_id: design.id }))

const history = must('reading the stage history', await asBuyer
  .from('milestone_events')
  .select('event, actor, occurred_at')
  .eq('milestone_id', design.id)
  .order('occurred_at'))

check('every round is on the record, including the one that was sent back',
  history.length === 4, history.map((h) => h.event).join(' '))
check('and it reads in the order it happened',
  history.map((h) => h.event).join(',') === 'deliver,request_revision,deliver,accept',
  history.map((h) => h.event).join(','))

step('The last stage carries the contract')

must('deliver the last', await asSeller.rpc('deliver_milestone', { p_milestone_id: build.id }))
check('delivering the last stage delivers the work',
  (await stateOf(asBuyer, contract.id)) === 'delivered')

must('accept the last', await asBuyer.rpc('accept_milestone', { p_milestone_id: build.id }))
check('and accepting it completes the contract, without a second signature',
  (await stateOf(asBuyer, contract.id)) === 'completed')

step('What the other party was told')

const told = must('reading the seller activity', await asSeller.rpc('my_notifications', { p_limit: 50 }))
const mine = told.filter((n) => n.transaction_id === contract.id && n.source === 'milestone')
check('the freelancer heard about the stage being sent back',
  mine.some((n) => n.event === 'request_revision' && n.needs_you === true),
  mine.map((n) => `${n.event}:${n.needs_you}`).join(' '))
check('and about it being accepted, as news rather than as a task',
  mine.some((n) => n.event === 'accept' && n.needs_you === false))

console.log(failures === 0
  ? '\nWork can now be agreed a stage at a time, and every round is on the record.\n'
  : `\n${failures} check(s) failed.\n`)
process.exitCode = failures === 0 ? 0 : 1
