/**
 * POST /functions/v1/file-evidence   (multipart/form-data)
 *
 *   file           the document itself
 *   transactionId  the contract it belongs to
 *   note           optional, what the uploader says about it
 *   contentType    optional, overrides the part's own type
 *   sha256         optional, the client's own digest, used only to catch a
 *                  corrupted transfer
 *
 * The bytes travel through this function on purpose.
 *
 * A signed upload URL would be lighter: the client would talk to storage
 * directly and this function would never hold the file. It would also mean the
 * server never sees the bytes, and therefore cannot compute their digest. The
 * digest is the thing every later guarantee rests on, including every finding
 * the model grounds in a document, so it is computed here from the bytes being
 * stored and never accepted from a client. Migration 0007 removed the client
 * INSERT policy on `evidence` and grants no storage write policy, which makes
 * this function the only way a row can exist.
 *
 * The cost is real: a 50 MiB upload is 50 MiB in this function's memory. If
 * that becomes the limit, the way out is a signed URL plus a server-side pass
 * that downloads the object, hashes it, and removes it when the row cannot be
 * written. That trade is worth making with numbers in hand, not before.
 *
 * Two identities, the same shape as resolve-dispute:
 *
 *   The caller's, to learn who they are. `auth.getUser()` verifies the token
 *   rather than trusting a claim in the body, so a user id can never be chosen
 *   by whoever is uploading.
 *
 *   The service role, to write. Storage and the evidence table are closed to
 *   clients by design; the party check happens in `uploadEvidence`, against the
 *   verified id.
 */

import { createClient } from '@supabase/supabase-js'
import {
  SupabaseEvidenceRepository,
  SupabaseObjectStorage,
  uploadEvidence,
  type UploadRejectionCode,
} from '@trustiq/server'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json' },
  })
}

/**
 * What each refusal means over HTTP.
 *
 * NOT_A_PARTY is 404 rather than 403, and deliberately: it fires both for a
 * contract that does not exist and for one that is simply not the caller's.
 * Telling those apart would confirm to a stranger that a given contract id is
 * real. resolve-dispute answers the same way for the same reason.
 */
const STATUS: Record<UploadRejectionCode, number> = {
  EMPTY_FILE: 400,
  FILE_TOO_LARGE: 413,
  UNSUPPORTED_CONTENT_TYPE: 415,
  INVALID_FILENAME: 400,
  DIGEST_MISMATCH: 400,
  NOT_A_PARTY: 404,
  TRANSACTION_CLOSED: 409,
  DUPLICATE_EVIDENCE: 409,
  STORAGE_FAILED: 500,
  RECORD_FAILED: 500,
}

function field(form: FormData, name: string): string | null {
  const value = form.get(name)
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (request.method !== 'POST') return json({ error: 'Use POST.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')

  if (!url || !serviceRoleKey || !anonKey) {
    console.error('file-evidence is missing Supabase configuration')
    return json({ error: 'The service is not configured.' }, 500)
  }

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'Sign in first.' }, 401)

  // Who the caller is, according to the auth server rather than according to
  // the caller. Everything below hangs off this id.
  const asCaller = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })

  const { data: identity, error: identityError } = await asCaller.auth.getUser()
  if (identityError || !identity?.user) {
    return json({ error: 'Your session is not valid. Sign in again.' }, 401)
  }
  const userId = identity.user.id

  let form: FormData
  try {
    form = await request.formData()
  } catch {
    return json({ error: 'Send the file as multipart/form-data.' }, 400)
  }

  const transactionId = field(form, 'transactionId')
  if (transactionId === null) return json({ error: 'transactionId is required.' }, 400)

  const file = form.get('file')
  if (!(file instanceof File)) return json({ error: 'A "file" part is required.' }, 400)

  // Some HTTP clients cannot set a part's content type, so an explicit field
  // wins when it is there. Either way the value is checked against the
  // allowlist and against the bucket's allowed_mime_types, so the worst a
  // wrong one achieves is getting its own upload refused.
  const contentType = field(form, 'contentType') ?? (file.type || '')

  const bytes = new Uint8Array(await file.arrayBuffer())

  const asSystem = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const result = await uploadEvidence(
    {
      transactionId,
      userId,
      filename: file.name,
      contentType,
      bytes,
      note: field(form, 'note'),
      ...(field(form, 'sha256') === null ? {} : { clientClaimedSha256: field(form, 'sha256') as string }),
    },
    {
      storage: new SupabaseObjectStorage(asSystem),
      repository: new SupabaseEvidenceRepository(asSystem),
      clock: { now: () => new Date() },
      newId: () => crypto.randomUUID(),
    },
  )

  if (!result.ok) {
    const status = STATUS[result.error.code]
    if (status >= 500) {
      // The caller gets the code so a client can react, but not the internal
      // detail: a storage or PostgREST message is for the logs.
      console.error(`file-evidence ${result.error.code}: ${result.error.message}`)
      return json({ error: 'The document could not be filed.', code: result.error.code }, status)
    }
    return json({ error: result.error.message, code: result.error.code }, status)
  }

  return json(
    {
      evidenceId: result.value.evidenceId,
      sha256: result.value.sha256,
      byteSize: result.value.byteSize,
      role: result.value.role,
      storagePath: result.value.storagePath,
      // Returned so a client can tell the uploader now that this document's
      // text could not be read, rather than leaving them to find out when a
      // resolution turns out to have been reached without it.
      extractionStatus: result.value.extractionStatus,
    },
    201,
  )
})
