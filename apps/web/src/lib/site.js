/**
 * The few facts every page needs, in one place.
 *
 * The publishable key is written here on purpose. It ships inside the Android
 * build already and is designed to be readable; the only thing it can reach on
 * this site is one insert policy on `beta_signups`, which grants no read of any
 * kind. Hiding it would be theatre, and the schema tests assert in both
 * directions that it opens nothing else.
 */

export const SUPABASE_URL = 'https://ieccihxvmlapfuhbjuxf.supabase.co'
export const SUPABASE_ANON_KEY = 'sb_publishable_LvMn5CI5ZJJLt6aXaACbcQ_tE237fV4'

export const SITE = 'https://mtieze.github.io/trustiq-uae'

/**
 * The stores, when there are stores.
 *
 * Empty until the listings exist, and every button that points at them reads
 * this to decide whether it is a link or a disabled label. A site that says
 * "Get it on Google Play" and goes nowhere is worse than one that says the app
 * is not out yet: the first is a broken promise, the second is a date.
 */
export const STORES = {
  appStore: '',
  googlePlay: '',
}

export const STORES_LIVE = Boolean(STORES.appStore || STORES.googlePlay)

/** Adds one address to the beta list. Never reads anything back; it cannot. */
export async function joinBeta({ email, note, source }) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/beta_signups`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ email: email.trim(), note: note?.trim() || null, source }),
  })

  if (response.ok) return { ok: true }

  // The database refuses a malformed address with a check constraint. Its
  // message names the constraint, which means nothing to anybody, so the one
  // failure a person can act on is written here instead.
  const body = await response.json().catch(() => null)
  const constraint = String(body?.message ?? '')
  if (response.status === 400 && constraint.includes('beta_signups_email_check')) {
    return { ok: false, reason: 'email' }
  }
  return { ok: false, reason: 'unknown' }
}
