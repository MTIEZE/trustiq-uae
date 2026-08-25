/**
 * Builds one real dispute in the live project, end to end.
 *
 *   node scripts/seed-live-dispute.mjs
 *
 * This is not a fixture loader. It drives the actual code: contracts move
 * through `apply_transaction_event`, evidence goes through `uploadEvidence`
 * with the Supabase adapters, and every rule the schema enforces gets a chance
 * to refuse. If the adapters are wrong, this is where it shows.
 *
 * Everything it creates is prefixed so `--clean` can remove it again. It reads
 * .env and prints no keys.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'
import { uploadEvidence } from '../packages/server/dist/index.js'
import {
  SupabaseEvidenceRepository,
  SupabaseObjectStorage,
} from '../packages/server/dist/supabase/repositories.js'

const TAG = 'seed-e2e'

/* ------------------------------------------------------------------ */

function env() {
  const raw = readFileSync('.env', 'utf8')
  const out = {}
  for (const line of raw.split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
    if (!out[k]) {
      console.error(`${k} is not set in .env`)
      process.exit(1)
    }
  }
  return out
}

const step = (text) => console.log(`\n${text}`)
const ok = (text) => console.log(`  ok  ${text}`)

function must(label, { data, error }) {
  if (error) {
    console.error(`\nFAILED at: ${label}\n  ${error.message}\n`)
    process.exit(1)
  }
  return data
}

/* ------------------------------------------------------------------ */

const cfg = env()
const db = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const cleaning = process.argv.includes('--clean')

/** Removes everything a previous run created. */
async function clean() {
  step('Removing anything a previous run left behind')

  const { data: users } = await db.auth.admin.listUsers({ perPage: 200 })
  let removed = 0
  for (const user of users?.users ?? []) {
    if (user.email?.includes(TAG)) {
      // Contracts, disputes, evidence and audit rows all cascade from the
      // profile, which cascades from the auth user.
      await db.auth.admin.deleteUser(user.id)
      removed += 1
    }
  }
  ok(`removed ${removed} seeded user(s) and everything that hung off them`)

  const { data: objects } = await db.storage.from('evidence').list(TAG)
  if (objects?.length) {
    await db.storage.from('evidence').remove(objects.map((o) => `${TAG}/${o.name}`))
    ok(`removed ${objects.length} stored object(s)`)
  }
}

/** A signed-in client acting as one of the seeded users. */
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

async function seed() {
  await clean()

  const password = `${TAG}-${crypto.randomUUID()}`
  const buyerEmail = `buyer.${TAG}@example.test`
  const sellerEmail = `seller.${TAG}@example.test`

  step('Creating two verified people')

  const buyer = must(
    'creating the buyer',
    await db.auth.admin.createUser({
      email: buyerEmail,
      password,
      email_confirm: true,
    }),
  ).user
  const seller = must(
    'creating the seller',
    await db.auth.admin.createUser({
      email: sellerEmail,
      password,
      email_confirm: true,
    }),
  ).user

  must(
    'creating profiles',
    await db.from('profiles').insert([
      {
        id: buyer.id,
        full_name: 'Ahmed Al-Rashid',
        email: buyerEmail,
        identity_verified_at: new Date().toISOString(),
        identity_provider: 'manual_review',
      },
      {
        id: seller.id,
        full_name: 'Sara Design Studio',
        email: sellerEmail,
        identity_verified_at: new Date().toISOString(),
        identity_provider: 'manual_review',
      },
    ]),
  )
  ok('both profiles exist and are verified')

  step('Creating the contract as the buyer, through their own session')

  // Written with the buyer's token, so row level security has to allow it. A
  // service-role insert here would prove nothing about the policies.
  const asBuyer = await actAs(buyerEmail, password)
  const contract = must(
    'creating the contract',
    await asBuyer
      .from('transactions')
      .insert({
        buyer_id: buyer.id,
        seller_id: seller.id,
        description: `Logo design for a startup [${TAG}]`,
        terms:
          'Deliver 3 distinct logo concepts within 7 days. Two rounds of revision ' +
          'included. Final files supplied as SVG and PNG.',
        total_amount_fils: 50000,
        created_by: buyer.id,
      })
      .select('id, state, total_amount_fils')
      .single(),
  )
  ok(`contract ${contract.id} created as ${contract.state}`)

  step('Walking it to a delivered state through the state machine')

  const asSeller = await actAs(sellerEmail, password)

  must('submit', await asBuyer.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'submit',
  }))
  ok('buyer submitted')

  must('accept', await asSeller.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'accept',
  }))
  ok('seller accepted — the identity gate let it through')

  // The buyer must not be able to declare delivery. If this succeeds, the
  // actor rules are not doing their job in production.
  const { error: wrongActor } = await asBuyer.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'mark_delivered',
  })
  if (!wrongActor) {
    console.error('\nFAILED: the buyer was allowed to mark delivery\n')
    process.exit(1)
  }
  ok(`buyer refused delivery rights: ${wrongActor.message.slice(0, 70)}`)

  must('mark_delivered', await asSeller.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'mark_delivered',
  }))
  ok('seller marked it delivered')

  step('Filing evidence through the real upload path')

  const storage = new SupabaseObjectStorage(db)
  const repository = new SupabaseEvidenceRepository(db)
  const deps = {
    storage,
    repository,
    clock: { now: () => new Date() },
    newId: () => crypto.randomUUID(),
  }

  const brief = new TextEncoder().encode(
    'BRIEF\nThree distinct logo concepts, seven days, SVG and PNG.\nSigned 1 August 2026.',
  )
  const delivery = new TextEncoder().encode(
    'DELIVERY NOTE\nTwo concepts plus a colour variation, sent 8 August 2026.',
  )

  const filedBrief = await uploadEvidence(
    {
      transactionId: contract.id,
      userId: buyer.id,
      filename: 'signed-brief.txt',
      contentType: 'text/plain',
      bytes: brief,
      note: 'The brief we both agreed to.',
    },
    deps,
  )
  if (!filedBrief.ok) {
    console.error(`\nFAILED filing the brief: ${filedBrief.error.message}\n`)
    process.exit(1)
  }
  ok(`brief filed, digest computed by the server: ${filedBrief.value.sha256.slice(0, 16)}...`)

  const filedDelivery = await uploadEvidence(
    {
      transactionId: contract.id,
      userId: seller.id,
      filename: 'delivery-note.txt',
      contentType: 'text/plain',
      bytes: delivery,
      note: 'What was delivered, and when.',
    },
    deps,
  )
  if (!filedDelivery.ok) {
    console.error(`\nFAILED filing the delivery note: ${filedDelivery.error.message}\n`)
    process.exit(1)
  }
  ok(`delivery note filed: ${filedDelivery.value.sha256.slice(0, 16)}...`)

  // The same bytes twice must be refused, by the unique index rather than by
  // anything this script checks.
  const duplicate = await uploadEvidence(
    {
      transactionId: contract.id,
      userId: buyer.id,
      filename: 'same-bytes-different-name.txt',
      contentType: 'text/plain',
      bytes: brief,
      note: null,
    },
    deps,
  )
  if (duplicate.ok) {
    console.error('\nFAILED: the same file was accepted twice\n')
    process.exit(1)
  }
  ok(`a duplicate was refused: ${duplicate.error.code}`)

  step('Opening the dispute with both accounts')

  must('open_dispute', await asBuyer.rpc('apply_transaction_event', {
    p_transaction_id: contract.id,
    p_event: 'open_dispute',
  }))

  const dispute = must(
    'creating the dispute',
    await asBuyer
      .from('disputes')
      .insert({
        transaction_id: contract.id,
        opened_by: buyer.id,
        opened_by_role: 'buyer',
        buyer_claim:
          'Only two usable concepts were delivered. The third is a colour ' +
          'variation of the second, not a distinct concept as the brief required.',
        seller_claim:
          'Three concepts were delivered inside the agreed window. The client ' +
          'changed direction after seeing them.',
        disputed_amount_fils: contract.total_amount_fils,
      })
      .select('id, state')
      .single(),
  )
  ok(`dispute ${dispute.id} opened as ${dispute.state}`)

  step('Done')
  console.log(`
  Dispute id:   ${dispute.id}
  Contract id:  ${contract.id}
  Buyer:        ${buyerEmail}
  Seller:       ${sellerEmail}
  Password:     ${password}

  The dispute is 'open' with both accounts and two pieces of evidence, which
  is exactly the state resolve-dispute expects.

  Remove all of it with:  node scripts/seed-live-dispute.mjs --clean
`)
}

if (cleaning) {
  await clean()
  console.log('\nCleaned.\n')
} else {
  await seed()
}
