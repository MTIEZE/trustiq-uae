// Drains the notification outbox into email.
//
// Called on a schedule from .github/workflows/notify.yml, because the database
// has neither pg_net nor pg_cron and should not need them for this. The outbox
// was deliberately built inert: a contract transition must never fail because
// a mail provider is having a bad afternoon.
//
// What it does NOT do is describe the events. It says how many things are
// waiting and on which contracts, using the descriptions the parties wrote
// themselves, and points at the app. The vocabulary for transitions lives in
// the app in two languages behind tests, and a second copy here would drift
// from it the first time either changed. The mail is a nudge; the record is in
// the app.
//
// Every batch is marked, success or failure. A failure that left rows untouched
// would be retried forever against whatever is refusing them, and nobody would
// know it was happening.

// The npm specifier rather than the bare name: deno.json's import map is not
// uploaded by a single-file deploy, and rather than jsr, because npm is what
// the two functions already running here resolve to and demonstrably boot on.
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

/** Constant time, so a wrong key cannot be found one character at a time. */
function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

type Waiting = {
  recipient_id: string
  email: string
  full_name: string
  locale: string
  waiting: number
  contracts: string[]
  ids: number[]
}

const COPY = {
  en: {
    subject: (n: number) =>
      n === 1 ? 'Something is waiting for you on TrustIQ' : `${n} things are waiting for you on TrustIQ`,
    greeting: (name: string) => `${name},`,
    lead: (n: number) =>
      n === 1
        ? 'One move is waiting on you:'
        : `${n} moves are waiting on you, across these contracts:`,
    close: 'Open TrustIQ to see what happened and what to do next.',
    // Said plainly because it is the product's whole position, and because a
    // person who was not expecting mail from us deserves to know what this is.
    footer:
      'TrustIQ records what two people agreed. It never holds your money. ' +
      'You are getting this because you are a party to the contracts above.',
  },
  ar: {
    subject: (n: number) =>
      n === 1 ? 'هناك ما ينتظرك في TrustIQ' : `${n} أمور تنتظرك في TrustIQ`,
    greeting: (name: string) => `${name}،`,
    lead: (n: number) =>
      n === 1 ? 'إجراء واحد ينتظرك:' : `${n} إجراءات تنتظرك، على هذه العقود:`,
    close: 'افتح TrustIQ لترى ما حدث وما عليك فعله.',
    footer:
      'تسجّل TrustIQ ما اتفق عليه طرفان. ولا تحتفظ بأموالك أبداً. ' +
      'تصلك هذه الرسالة لأنك طرف في العقود أعلاه.',
  },
} as const

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function render(row: Waiting): { subject: string; html: string; text: string } {
  const copy = COPY[row.locale === 'ar' ? 'ar' : 'en']
  const rtl = row.locale === 'ar'

  const lines = row.contracts.map((c) => `- ${c}`).join('\n')
  const items = row.contracts
    .map((c) => `<li style="margin:0 0 6px">${escapeHtml(c)}</li>`)
    .join('')

  return {
    subject: copy.subject(row.waiting),
    text: [
      copy.greeting(row.full_name),
      '',
      copy.lead(row.waiting),
      lines,
      '',
      copy.close,
      '',
      copy.footer,
    ].join('\n'),
    html: `<div dir="${rtl ? 'rtl' : 'ltr'}" style="font-family:-apple-system,Segoe UI,system-ui,sans-serif;font-size:15px;line-height:1.6;color:#101614;max-width:520px">
  <p style="margin:0 0 14px">${escapeHtml(copy.greeting(row.full_name))}</p>
  <p style="margin:0 0 10px">${escapeHtml(copy.lead(row.waiting))}</p>
  <ul style="margin:0 0 18px;padding-${rtl ? 'right' : 'left'}:20px">${items}</ul>
  <p style="margin:0 0 22px">${escapeHtml(copy.close)}</p>
  <p style="margin:0;padding-top:14px;border-top:1px solid #DCE3DF;font-size:12.5px;color:#7C8783">${escapeHtml(copy.footer)}</p>
</div>`,
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (request.method !== 'POST') return json({ error: 'Use POST.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const brevoKey = Deno.env.get('BREVO_API_KEY')
  const sender = Deno.env.get('SMTP_SENDER_EMAIL')

  // This one first, and only this one: without the service role key there is
  // nothing to authenticate against, so the request cannot be judged at all.
  if (!url || !serviceRoleKey) {
    console.error('send-notifications is missing Supabase configuration')
    return json({ error: 'The service is not configured.' }, 500)
  }

  // Only the holder of the service role may run this. It reads addresses and
  // sends mail; there is no version of this that a signed-in person should be
  // able to trigger, let alone an anonymous one.
  //
  // Before the remaining configuration checks, not after. Answering an
  // unauthorised caller with "the service is not configured" tells them
  // something about the service, and whether our mail is set up is none of
  // their business.
  const bearer = (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!bearer || !sameSecret(bearer, serviceRoleKey)) {
    return json({ error: 'Not for you.' }, 401)
  }

  if (!brevoKey || !sender) {
    console.error('send-notifications is missing BREVO_API_KEY or SMTP_SENDER_EMAIL')
    return json({ error: 'The service is not configured.' }, 500)
  }

  const db = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data, error } = await db.rpc('notifications_to_send', {})
  if (error) {
    console.error(`could not read the outbox: ${error.message}`)
    return json({ error: 'Could not read the outbox.' }, 500)
  }

  const batches = (data ?? []) as Waiting[]
  let sent = 0
  let failed = 0

  for (const row of batches) {
    const { subject, html, text } = render(row)
    let failure: string | null = null

    try {
      const response = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          'api-key': brevoKey,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify({
          sender: { email: sender, name: 'TrustIQ' },
          to: [{ email: row.email, name: row.full_name }],
          subject,
          htmlContent: html,
          textContent: text,
        }),
      })

      if (!response.ok) {
        // Kept short and kept out of the logs verbatim: a provider error can
        // echo back the address it was given.
        failure = `brevo ${response.status}`
      }
    } catch (e) {
      failure = `network: ${e instanceof Error ? e.name : 'unknown'}`
    }

    const { error: markError } = await db.rpc('mark_notifications_sent', {
      p_ids: row.ids,
      p_error: failure,
    })
    if (markError) {
      // Worth shouting about: unmarked rows will be picked up again next run
      // and the same person gets the same mail every fifteen minutes.
      console.error(`could not mark a batch as sent: ${markError.message}`)
    }

    if (failure) {
      failed += 1
      console.error(`batch for one recipient failed: ${failure}`)
    } else {
      sent += 1
    }
  }

  return json({ recipients: batches.length, sent, failed })
})
