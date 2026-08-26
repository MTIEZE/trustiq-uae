/**
 * Exercises the file-evidence endpoint over real HTTP.
 *
 *   node scripts/test-file-evidence.mjs [baseUrl]
 *
 * Default base URL is the local runtime:
 *
 *   npx supabase functions serve --env-file .env
 *
 * Point it at the deployed function instead by passing its URL.
 *
 * The layers below this endpoint are covered elsewhere: `uploadEvidence` has
 * unit tests, the adapters are driven by seed-live-dispute.mjs, and the schema
 * has its own suite. What has no other cover is the HTTP layer itself: whether
 * multipart parsing works, whether the caller's identity really comes from
 * their token, and whether each refusal comes back as the right status. That
 * is what this checks, against the live database, with real sessions.
 *
 * It uploads to the most recent seeded contract, so run seed-live-dispute.mjs
 * first. What it files cannot be deleted afterwards: evidence is append-only.
 */

import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'

const BASE = process.argv[2] ?? 'http://127.0.0.1:54321/functions/v1'
const ENDPOINT = `${BASE.replace(/\/$/, '')}/file-evidence`

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
  for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
    if (!out[k]) {
      console.error(`${k} is not set in .env`)
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
let failures = 0
function check(condition, label, detail) {
  if (condition) {
    console.log(`  ok  ${label}`)
  } else {
    console.log(`  !!  ${label}${detail === undefined ? '' : `\n        ${detail}`}`)
    failures += 1
  }
}

/** POSTs one multipart request and returns { status, body }. */
async function post({ token, transactionId, filename, contentType, bytes, note, sha256 }) {
  const form = new FormData()
  if (transactionId !== undefined) form.set('transactionId', transactionId)
  if (bytes !== undefined) {
    form.set('file', new Blob([bytes], { type: contentType ?? '' }), filename ?? 'file.txt')
  }
  if (contentType !== undefined) form.set('contentType', contentType)
  if (note !== undefined) form.set('note', note)
  if (sha256 !== undefined) form.set('sha256', sha256)

  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: token === undefined ? {} : { Authorization: `Bearer ${token}` },
    body: form,
  })

  const text = await response.text()
  let body
  try {
    body = JSON.parse(text)
  } catch {
    body = { raw: text.slice(0, 300) }
  }
  return { status: response.status, body }
}

/* ------------------------------------------------------------------ */

step(`Endpoint: ${ENDPOINT}`)

step('Finding the seeded contract and its parties')

const { data: contracts, error: contractError } = await db
  .from('transactions')
  .select('id, state, buyer_id, seller_id, description, created_at')
  .like('description', '%[seed-e2e-%')
  .order('created_at', { ascending: false })
  .limit(1)

if (contractError) {
  console.error(`  could not read contracts: ${contractError.message}`)
  process.exit(1)
}
if (!contracts?.length) {
  console.error('\n  No seeded contract found. Run: node scripts/seed-live-dispute.mjs\n')
  process.exit(1)
}
const contract = contracts[0]
console.log(`  contract ${contract.id} (${contract.state})`)

const { data: buyerProfile } = await db
  .from('profiles')
  .select('email')
  .eq('id', contract.buyer_id)
  .single()

// The seed script prints the password but does not store it, so a fresh one is
// set here through the admin API. These are throwaway test identities.
const password = `probe-${crypto.randomUUID()}`
await db.auth.admin.updateUserById(contract.buyer_id, { password })

const anon = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const { data: session, error: signInError } = await anon.auth.signInWithPassword({
  email: buyerProfile.email,
  password,
})
if (signInError) {
  console.error(`  could not sign in as the buyer: ${signInError.message}`)
  process.exit(1)
}
const buyerToken = session.session.access_token
console.log(`  signed in as ${buyerProfile.email}`)

// A third person, party to nothing. Created once and reused across runs.
const outsiderEmail = 'outsider.seed-e2e@example.test'
const outsiderPassword = `probe-${crypto.randomUUID()}`
const { data: existing } = await db.auth.admin.listUsers({ perPage: 200 })
const found = existing?.users?.find((u) => u.email === outsiderEmail)
let outsiderId
if (found) {
  outsiderId = found.id
  await db.auth.admin.updateUserById(outsiderId, { password: outsiderPassword })
} else {
  const { data: made, error } = await db.auth.admin.createUser({
    email: outsiderEmail,
    password: outsiderPassword,
    email_confirm: true,
  })
  if (error) {
    console.error(`  could not create the outsider: ${error.message}`)
    process.exit(1)
  }
  outsiderId = made.user.id
  await db.from('profiles').insert({
    id: outsiderId,
    full_name: 'Nosy Person',
    email: outsiderEmail,
  })
}
const { data: outsiderSession, error: outsiderError } = await anon.auth.signInWithPassword({
  email: outsiderEmail,
  password: outsiderPassword,
})
if (outsiderError) {
  console.error(`  could not sign in as the outsider: ${outsiderError.message}`)
  process.exit(1)
}
const outsiderToken = outsiderSession.session.access_token
console.log(`  signed in as ${outsiderEmail}, who is party to nothing`)

/* ------------------------------------------------------------------ */

step('Refusals that must come before anything is stored')

{
  const r = await post({ transactionId: contract.id, bytes: new TextEncoder().encode('x'), contentType: 'text/plain' })
  check(r.status === 401, `no token is refused with 401 (got ${r.status})`, JSON.stringify(r.body))
}

{
  const r = await post({ token: 'not-a-real-token', transactionId: contract.id, bytes: new TextEncoder().encode('x'), contentType: 'text/plain' })
  check(r.status === 401, `a forged token is refused with 401 (got ${r.status})`, JSON.stringify(r.body))
}

{
  const r = await post({ token: buyerToken, bytes: new TextEncoder().encode('x'), contentType: 'text/plain' })
  check(r.status === 400, `a missing transactionId is refused with 400 (got ${r.status})`, JSON.stringify(r.body))
}

{
  const r = await post({ token: buyerToken, transactionId: contract.id })
  check(r.status === 400, `a missing file part is refused with 400 (got ${r.status})`, JSON.stringify(r.body))
}

{
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes: new Uint8Array(0),
    contentType: 'text/plain',
    filename: 'empty.txt',
  })
  check(r.body?.code === 'EMPTY_FILE', `an empty file is refused (${r.status} ${r.body?.code})`)
}

{
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes: new TextEncoder().encode('<script>alert(1)</script>'),
    contentType: 'text/html',
    filename: 'page.html',
  })
  check(
    r.status === 415 && r.body?.code === 'UNSUPPORTED_CONTENT_TYPE',
    `an unsupported content type is refused with 415 (${r.status} ${r.body?.code})`,
  )
}

{
  // A plain separator, not a traversal signature. This is the one that proves
  // our own rule: `../../etc/passwd` never reaches the function, because the
  // WAF in front of Supabase answers it with a 403 HTML page first. Asserting
  // INVALID_FILENAME on that input tested the edge, not this codebase.
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes: new TextEncoder().encode('separator attempt'),
    contentType: 'text/plain',
    filename: 'sub/dir.txt',
  })
  check(
    r.body?.code === 'INVALID_FILENAME',
    `a filename with a path separator is refused by the function (${r.status} ${r.body?.code})`,
  )
}

{
  // And the traversal signature is refused by something, which is all this can
  // honestly claim: against the deployed function the WAF answers first, and
  // against a local run the function does. Both are refusals; only the status
  // differs, so only the refusal is asserted.
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes: new TextEncoder().encode('traversal attempt'),
    contentType: 'text/plain',
    filename: '../../etc/passwd',
  })
  check(
    r.status >= 400,
    `a path traversal in a filename never lands (${r.status} ${r.body?.code ?? 'refused upstream'})`,
  )
}

{
  // The point of the whole endpoint: the caller cannot choose whose upload
  // this is. The outsider holds a valid session and is still not a party.
  const r = await post({
    token: outsiderToken,
    transactionId: contract.id,
    bytes: new TextEncoder().encode('I should not be able to file this.'),
    contentType: 'text/plain',
    filename: 'outsider.txt',
  })
  check(
    r.status === 404 && r.body?.code === 'NOT_A_PARTY',
    `a stranger with a valid session is refused with 404 (${r.status} ${r.body?.code})`,
  )
}

{
  const r = await post({
    token: buyerToken,
    transactionId: '00000000-0000-4000-8000-000000000000',
    bytes: new TextEncoder().encode('nowhere'),
    contentType: 'text/plain',
    filename: 'nowhere.txt',
  })
  check(
    r.status === 404,
    `an unknown contract gets the same 404, so existence is not confirmed (${r.status} ${r.body?.code})`,
  )
}

{
  const bytes = new TextEncoder().encode('These bytes do not match the digest below.')
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes,
    contentType: 'text/plain',
    filename: 'corrupted.txt',
    sha256: 'f'.repeat(64),
  })
  check(
    r.body?.code === 'DIGEST_MISMATCH',
    `a mismatched client digest is refused (${r.status} ${r.body?.code})`,
  )
}

const { count: beforeCount } = await db
  .from('evidence')
  .select('id', { count: 'exact', head: true })
  .eq('transaction_id', contract.id)

/* ------------------------------------------------------------------ */

step('The upload that should work')

const content = `PROBE ${new Date().toISOString()}\nFiled through the file-evidence endpoint.`
const bytes = new TextEncoder().encode(content)
const expected = createHash('sha256').update(bytes).digest('hex')

const filed = await post({
  token: buyerToken,
  transactionId: contract.id,
  bytes,
  contentType: 'text/plain',
  filename: 'endpoint-probe.txt',
  note: 'Filed by scripts/test-file-evidence.mjs',
  sha256: expected,
})

check(filed.status === 201, `the upload returns 201 (got ${filed.status})`, JSON.stringify(filed.body))
check(filed.body?.sha256 === expected, 'the digest the server computed matches the bytes that were sent')
check(filed.body?.byteSize === bytes.byteLength, `the byte size is reported correctly (${filed.body?.byteSize})`)
check(filed.body?.role === 'buyer', `the role was derived from the token, not sent (${filed.body?.role})`)
check(typeof filed.body?.evidenceId === 'string', 'an evidence id came back')
check(
  filed.body?.extractionStatus === 'extracted',
  `the text was read at upload (${filed.body?.extractionStatus})`,
)

step('Reading the row back')

if (filed.body?.evidenceId) {
  const { data: row } = await db
    .from('evidence')
    .select('transaction_id, uploaded_by, uploaded_by_role, sha256, byte_size, filename, content_type, note, storage_path, extracted_text, extraction_status')
    .eq('id', filed.body.evidenceId)
    .maybeSingle()

  check(row !== null, 'the evidence row exists in the database')
  if (row) {
    check(row.sha256 === expected, 'the stored digest is the one the server computed')
    check(row.uploaded_by === contract.buyer_id, 'the row credits the signed-in user')
    check(row.uploaded_by_role === 'buyer', 'the stored role matches the side of the contract')
    check(Number(row.byte_size) === bytes.byteLength, 'the stored byte size is right')
    check(row.filename === 'endpoint-probe.txt', 'the filename was kept as metadata')
    check(row.extraction_status === 'extracted', `the row records that the text was read (${row.extraction_status})`)
    check(
      row.extracted_text === content,
      'the stored text is what the file actually said, so the model reads the document rather than its name',
    )

    const { data: object, error: objectError } = await db.storage
      .from('evidence')
      .download(row.storage_path)
    check(objectError === null && object !== null, 'the object is really in the bucket')
    if (object) {
      const stored = new Uint8Array(await object.arrayBuffer())
      const storedDigest = createHash('sha256').update(stored).digest('hex')
      check(
        storedDigest === expected,
        'the bytes in the bucket hash to the digest in the row, so the record describes the file',
      )
    }
  }
}

step('The same file twice')

{
  const r = await post({
    token: buyerToken,
    transactionId: contract.id,
    bytes,
    contentType: 'text/plain',
    filename: 'a-different-name.txt',
  })
  check(
    r.status === 409 && r.body?.code === 'DUPLICATE_EVIDENCE',
    `the same bytes under another name are refused with 409 (${r.status} ${r.body?.code})`,
  )
}

const { count: afterCount } = await db
  .from('evidence')
  .select('id', { count: 'exact', head: true })
  .eq('transaction_id', contract.id)

check(
  (afterCount ?? 0) === (beforeCount ?? 0) + 1,
  `exactly one row was added across all of it (${beforeCount} then ${afterCount})`,
)

/* ------------------------------------------------------------------ */

step(failures === 0 ? 'All checks passed.' : `${failures} check(s) failed.`)
process.exit(failures === 0 ? 0 : 1)
