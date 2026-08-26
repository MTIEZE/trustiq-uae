/**
 * Checks a live Supabase project against what the schema is supposed to
 * guarantee.
 *
 *   node scripts/verify-supabase.mjs
 *
 * Reads .env. Never prints a key, only whether one is present and what it can
 * and cannot do.
 *
 * The checks are behavioural rather than introspective on purpose. Reading
 * pg_class tells you what the catalog says; trying to insert a row with a
 * public key tells you what actually happens to a stranger with your app's
 * bundle open in front of them. The second is the question worth asking.
 */

import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

/* ------------------------------------------------------------------ */

function readEnv(path = '.env') {
  let raw
  try {
    raw = readFileSync(path, 'utf8')
  } catch {
    fail(
      'No .env file.\n\n' +
        '  cp .env.example .env\n\n' +
        'Then fill SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY\n' +
        'from Project Settings > API in the Supabase dashboard.',
    )
  }

  const env = {}
  for (const line of raw.split('\n')) {
    const trimmed = line.trim()
    if (trimmed === '' || trimmed.startsWith('#')) continue
    const at = trimmed.indexOf('=')
    if (at === -1) continue
    env[trimmed.slice(0, at).trim()] = trimmed.slice(at + 1).trim()
  }
  return env
}

function fail(message) {
  console.error(`\n${message}\n`)
  process.exit(1)
}

const results = []
function record(ok, label, detail = '') {
  results.push({ ok, label, detail })
  const mark = ok ? '  ok  ' : ' FAIL '
  console.log(`${mark}${label}${detail ? `\n        ${detail}` : ''}`)
}

/* ------------------------------------------------------------------ */

const env = readEnv()

for (const key of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
  if (!env[key]) fail(`${key} is not set in .env.`)
}

// Guard against the mistake this whole file exists to catch. If the two keys
// are the same value, one of them was pasted into the wrong slot, and every
// check below would pass for the wrong reason.
if (env.SUPABASE_ANON_KEY === env.SUPABASE_SERVICE_ROLE_KEY) {
  fail(
    'SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY hold the same value.\n' +
      'One of them was pasted into the wrong line. They are different keys with\n' +
      'very different powers; copy them again from Project Settings > API.',
  )
}

const options = { auth: { persistSession: false, autoRefreshToken: false } }
const asPublic = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, options)
const asServer = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, options)

console.log(`\nChecking ${env.SUPABASE_URL}\n`)

/* --- the schema is there ------------------------------------------ */

console.log('The schema')

const TABLES = [
  'profiles',
  'transactions',
  'milestones',
  'transaction_events',
  'evidence',
  'disputes',
  'resolution_proposals',
  'resolution_findings',
  'resolution_finding_evidence',
  'dispute_acceptances',
  'dispute_events',
  'ai_call_log',
]

const missing = []
for (const table of TABLES) {
  const { error } = await asServer.from(table).select('*', { count: 'exact', head: true })
  if (error) missing.push(`${table} (${error.message})`)
}
record(
  missing.length === 0,
  `all ${TABLES.length} tables exist`,
  missing.length ? `missing or unreadable: ${missing.join(', ')}` : '',
)

/* --- row level security is actually on ---------------------------- */

console.log('\nRow level security')

// A public caller with no session must see nothing. If RLS were off, or a
// policy were missing, this returns rows instead of an empty list.
const { data: publicTxns, error: publicTxnError } = await asPublic
  .from('transactions')
  .select('id')
  .limit(1)

record(
  !publicTxnError && Array.isArray(publicTxns) && publicTxns.length === 0,
  'a signed-out caller sees no contracts',
  publicTxnError
    ? `unexpected error: ${publicTxnError.message}`
    : publicTxns?.length
      ? `returned ${publicTxns.length} row(s) — RLS is not protecting this table`
      : '',
)

const { data: publicEvidence } = await asPublic.from('evidence').select('id').limit(1)
record(
  Array.isArray(publicEvidence) && publicEvidence.length === 0,
  'a signed-out caller sees no evidence',
  publicEvidence?.length ? `returned ${publicEvidence.length} row(s)` : '',
)

// The one that matters most: prompts and raw model output stay internal.
const { data: publicAudit } = await asPublic.from('ai_call_log').select('id').limit(1)
record(
  Array.isArray(publicAudit) && publicAudit.length === 0,
  'a signed-out caller sees no model call log',
  publicAudit?.length ? `returned ${publicAudit.length} row(s)` : '',
)

/* --- the evidence digest hole stays closed ------------------------ */

console.log('\nEvidence is server-written only')

const { error: insertError } = await asPublic.from('evidence').insert({
  transaction_id: '00000000-0000-0000-0000-000000000000',
  uploaded_by: '00000000-0000-0000-0000-000000000000',
  uploaded_by_role: 'buyer',
  storage_path: 'verify/probe',
  filename: 'probe.pdf',
  content_type: 'application/pdf',
  byte_size: 1,
  sha256: 'f'.repeat(64),
})

record(
  insertError !== null,
  'a client cannot insert an evidence row',
  insertError === null
    ? 'THE INSERT SUCCEEDED. A party could choose its own digest; migration 0007 did not apply.'
    : `refused: ${insertError.message}`,
)

/* --- storage ------------------------------------------------------ */

console.log('\nStorage')

const { data: buckets, error: bucketError } = await asServer.storage.listBuckets()
const evidenceBucket = buckets?.find((b) => b.id === 'evidence')

record(
  evidenceBucket !== undefined,
  'the evidence bucket exists',
  bucketError ? bucketError.message : evidenceBucket ? '' : 'not found',
)

if (evidenceBucket) {
  record(
    evidenceBucket.public === false,
    'the evidence bucket is private',
    evidenceBucket.public ? 'IT IS PUBLIC. Every filed document is world-readable.' : '',
  )
}

const { error: publicUploadError } = await asPublic.storage
  .from('evidence')
  .upload('verify/probe.txt', new Uint8Array([1]), { contentType: 'text/plain' })

record(
  publicUploadError !== null,
  'a client cannot write to the bucket',
  publicUploadError === null
    ? 'THE UPLOAD SUCCEEDED. A stored file could be swapped after its digest was recorded.'
    : `refused: ${publicUploadError.message}`,
)

/* --- the state machine functions ---------------------------------- */

console.log('\nState machine')

// Called with an id that does not exist. A "not found" answer proves the
// function is there and running; a "does not exist" answer means it is not.
const { error: rpcError } = await asServer.rpc('apply_transaction_event', {
  p_transaction_id: '00000000-0000-0000-0000-000000000000',
  p_event: 'submit',
})

record(
  rpcError !== null && !/could not find|does not exist|schema cache/i.test(rpcError.message),
  'apply_transaction_event is installed',
  rpcError === null
    ? 'it accepted a transaction that does not exist'
    : `responded: ${rpcError.message}`,
)

const { error: disputeRpcError } = await asServer.rpc('apply_dispute_event', {
  p_dispute_id: '00000000-0000-0000-0000-000000000000',
  p_event: 'submit_for_ai',
})

record(
  disputeRpcError !== null &&
    !/could not find|does not exist|schema cache/i.test(disputeRpcError.message),
  'apply_dispute_event is installed',
  disputeRpcError === null
    ? 'it accepted a dispute that does not exist'
    : `responded: ${disputeRpcError.message}`,
)

/* --- money is an integer type ------------------------------------- */

console.log('\nMoney')

// Postgres rejects a fractional value for the fils domain. If this succeeds,
// the column is not what the migrations say it is.
const { error: fractionError } = await asServer.from('transactions').insert({
  id: '00000000-0000-0000-0000-000000000001',
  buyer_id: '00000000-0000-0000-0000-000000000000',
  seller_id: '00000000-0000-0000-0000-000000000002',
  description: 'verification probe',
  terms: 'verification probe',
  total_amount_fils: 100.5,
  created_by: '00000000-0000-0000-0000-000000000000',
})

record(
  fractionError !== null,
  'a fractional amount is refused',
  fractionError === null
    ? 'IT WAS ACCEPTED. total_amount_fils is not an integer column.'
    : `refused: ${fractionError.message}`,
)

/* ------------------------------------------------------------------ */

const failed = results.filter((r) => !r.ok)
console.log(`\n${results.length - failed.length}/${results.length} checks passed`)

if (failed.length > 0) {
  console.log('\nFailed:')
  for (const f of failed) console.log(`  - ${f.label}`)
  console.log(
    '\nIf the tables are missing, the migrations did not apply. If a table exists\n' +
      'but a client can read or write it, a policy from a later migration is\n' +
      'missing: apply them in filename order, all the way to 0007.',
  )
  process.exit(1)
}

console.log('\nThe project matches what the schema promises.\n')
