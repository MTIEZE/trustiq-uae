/**
 * Building Supabase clients, and keeping the two kinds apart.
 *
 * There are two keys and they are not interchangeable:
 *
 *   anon          Goes in the apps. Row level security decides what each
 *                 signed-in person can see and do, which is the whole point of
 *                 the schema in supabase/migrations.
 *
 *   service_role  Bypasses row level security entirely. It belongs only in a
 *                 process you control, never in a Flutter build, a web bundle,
 *                 or anything a person can open. Shipping it would hand every
 *                 user read and write access to every contract in the system.
 *
 * The functions below take the key as an argument rather than reading it
 * themselves, so a caller cannot pick one up by accident, and the service-role
 * one is named so that using it is a visible decision in a diff.
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export interface SupabaseConnection {
  readonly url: string
  readonly key: string
}

export function readConnectionFromEnv(env: Record<string, string | undefined>): {
  url: string
  serviceRoleKey: string
} {
  const url = env['SUPABASE_URL']
  const serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY']

  const missing: string[] = []
  if (url === undefined || url.length === 0) missing.push('SUPABASE_URL')
  if (serviceRoleKey === undefined || serviceRoleKey.length === 0) {
    missing.push('SUPABASE_SERVICE_ROLE_KEY')
  }
  if (missing.length > 0) {
    throw new Error(
      `Supabase is not configured: ${missing.join(', ')} is missing. ` +
        'See .env.example. Never commit these values.',
    )
  }

  return { url: url as string, serviceRoleKey: serviceRoleKey as string }
}

/**
 * A client that bypasses row level security.
 *
 * Only for server-side work that legitimately acts outside any one user's
 * permissions: the evidence upload path, the resolution run, scheduled jobs.
 * Sessions are disabled because there is no user to persist.
 */
export function createServiceRoleClient(connection: SupabaseConnection): SupabaseClient {
  return createClient(connection.url, connection.key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

/**
 * A client acting as one signed-in person, with RLS applied.
 *
 * Used when a request should be able to do exactly what its user can do and
 * nothing more. Prefer this: the service-role client is the exception, not the
 * default, and every use of it is a place where the schema's protections are
 * switched off deliberately.
 */
export function createUserClient(
  connection: SupabaseConnection,
  accessToken: string,
): SupabaseClient {
  return createClient(connection.url, connection.key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  })
}
