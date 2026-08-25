/**
 * POST /functions/v1/resolve-dispute  { "disputeId": "..." }
 *
 * Runs one dispute through the resolution pipeline.
 *
 * Two identities are involved, deliberately:
 *
 *   The caller's, to decide whether this dispute is any of their business. The
 *   check is a read through their own token, so row level security answers the
 *   question rather than this function re-deciding it.
 *
 *   The service role, to do the work. Writing a proposal, moving the dispute
 *   through its states and appending to the audit log are system actions; the
 *   schema reserves them for `system` precisely so a party cannot perform them.
 *
 * Authorising as the user and acting as the system is the whole shape of this
 * file. Skipping the first would let anyone spend model budget on anyone
 * else's case; skipping the second would have the database refuse the writes.
 */

import { createClient } from '@supabase/supabase-js'
import { filsFromAed } from '@trustiq/core'
import { createAnthropicClient } from '@trustiq/ai'
import { runResolution, SupabaseDisputeRepository } from '@trustiq/server'

/** Above this, or below the confidence floor, a person decides instead. */
const POLICY = {
  minConfidence: 0.7,
  maxAutoAmount: filsFromAed('5000'),
}

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

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (request.method !== 'POST') return json({ error: 'Use POST.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')

  if (!url || !serviceRoleKey || !anonKey) {
    // A configuration problem, not the caller's fault, and not something to
    // describe in detail to whoever is on the other end.
    console.error('resolve-dispute is missing Supabase configuration')
    return json({ error: 'The service is not configured.' }, 500)
  }
  if (!anthropicKey) {
    console.error('resolve-dispute is missing ANTHROPIC_API_KEY')
    return json({ error: 'The service is not configured.' }, 500)
  }

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'Sign in first.' }, 401)

  let disputeId: unknown
  try {
    disputeId = (await request.json())?.disputeId
  } catch {
    return json({ error: 'Send a JSON body.' }, 400)
  }
  if (typeof disputeId !== 'string' || disputeId.length === 0) {
    return json({ error: 'disputeId is required.' }, 400)
  }

  // Authorise as the caller. If row level security does not show them this
  // dispute, they are not a party to it, and there is nothing more to say.
  const asCaller = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })

  const { data: visible, error: visibleError } = await asCaller
    .from('disputes')
    .select('id, state')
    .eq('id', disputeId)
    .maybeSingle()

  if (visibleError) {
    console.error('authorisation read failed', visibleError.message)
    return json({ error: 'Could not check your access to this dispute.' }, 500)
  }
  if (visible === null) {
    // Deliberately the same answer whether the dispute is missing or simply
    // not theirs. Telling a stranger which one it is confirms that a given
    // dispute exists.
    return json({ error: 'No such dispute.' }, 404)
  }

  if (visible.state !== 'open') {
    return json(
      {
        error: `This dispute is ${visible.state}, not open. Analysis runs once, when both accounts are in.`,
      },
      409,
    )
  }

  // Act as the system. Every write below is one the schema reserves for
  // `system`, which is exactly why a party's token cannot make them.
  const asSystem = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const result = await runResolution(disputeId, {
    repository: new SupabaseDisputeRepository(asSystem),
    model: createAnthropicClient({ apiKey: anthropicKey }),
    policy: POLICY,
    clock: { now: () => new Date() },
  })

  switch (result.kind) {
    case 'proposal':
      return json({ outcome: 'proposal', proposalId: result.proposalId })
    case 'escalated':
      // Not an error: a case going to a human is a designed outcome, and the
      // caller needs to be told so rather than shown a failure.
      return json({ outcome: 'escalated', reason: result.reason })
    case 'skipped':
      return json({ outcome: 'skipped', reason: result.reason }, 404)
    default: {
      // Unreachable while RunResult has three shapes. If a fourth is added,
      // this stops compiling rather than silently returning nothing.
      const unhandled: never = result
      console.error('unhandled run result', unhandled)
      return json({ error: 'The run produced an unexpected result.' }, 500)
    }
  }
})
