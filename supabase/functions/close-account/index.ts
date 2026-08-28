// Closes the caller's own account.
//
// Two halves that have to happen together and cannot happen in the same place.
// The database empties or removes the profile; auth still holds a sign-in with
// their address on it, and that lives behind the admin API. A profile with no
// name attached to an account that can still receive a password reset is not a
// closed account.
//
// The caller is authenticated as themselves and the id acted on is the one the
// token carries, never one they send. Otherwise this endpoint would be a way
// to close somebody else's account, which is the worst thing an endpoint can
// be talked into doing.

import { createClient } from 'npm:@supabase/supabase-js@^2.112.4'

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

  if (!url || !serviceRoleKey || !anonKey) {
    console.error('close-account is missing Supabase configuration')
    return json({ error: 'The service is not configured.' }, 500)
  }

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'Sign in first.' }, 401)

  // Who they are, established from the token rather than taken on trust. The
  // request body is not read at all: there is nothing it could usefully say.
  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: who, error: whoError } = await asCaller.auth.getUser()
  if (whoError || !who?.user) return json({ error: 'Sign in first.' }, 401)

  const userId = who.user.id
  const db = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data, error } = await db.rpc('close_account', { p_user_id: userId })
  if (error) {
    console.error(`close_account failed: ${error.message}`)
    return json({ error: 'The account could not be closed.' }, 500)
  }

  const result = Array.isArray(data) ? data[0] : data
  const outcome = result?.outcome ?? 'anonymised'
  const kept: string | null = result?.kept ?? null

  // The sign-in, second. If this fails the profile is already empty, which is
  // the half that matters for privacy, and the account can still be closed by
  // hand. The other order would leave somebody locked out of an account that
  // still carries their name.
  if (outcome === 'deleted') {
    const { error: gone } = await db.auth.admin.deleteUser(userId)
    if (gone) console.error(`profile deleted but auth user remains: ${gone.message}`)
  } else {
    // Not deletable: the profile row still exists and auth.users cascades into
    // it, so the foreign keys that made anonymising necessary would refuse
    // this too. Take the address off it and shut the door instead.
    const { error: banned } = await db.auth.admin.updateUserById(userId, {
      email: `closed-${userId.replace(/-/g, '')}@deleted.invalid`,
      // A hundred years. There is no "forever" in this API and a date nobody
      // alive will see is the honest way to spell one.
      ban_duration: '876000h',
    })
    if (banned) console.error(`profile anonymised but sign-in remains: ${banned.message}`)
  }

  return json({ outcome, kept })
})
