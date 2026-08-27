/**
 * Asks the mail server directly whether the credentials work.
 *
 *   node scripts/test-smtp.mjs
 *
 * "Error sending confirmation email" is all Supabase will tell you. The reason
 * is whatever the SMTP server said, and the SMTP server will say it plainly if
 * you ask. This connects, upgrades to TLS, authenticates, and prints the
 * server's own words.
 *
 * It never prints the credentials, only what the server answers. It sends no
 * mail: it stops after AUTH.
 */

import { readFileSync } from 'node:fs'
import net from 'node:net'
import tls from 'node:tls'

function env() {
  const out = {}
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const at = t.indexOf('=')
    if (at !== -1) out[t.slice(0, at).trim()] = t.slice(at + 1).trim()
  }
  return out
}

const cfg = env()
const host = cfg.SMTP_HOST
const port = Number(cfg.SMTP_PORT || 587)

for (const k of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS']) {
  if (!cfg[k]) {
    console.error(`\n  ${k} is not set in .env\n`)
    process.exit(1)
  }
}

/// Reads until a line that is a complete reply (code followed by a space).
function reply(socket) {
  return new Promise((resolve, reject) => {
    let buffer = ''
    const onData = (chunk) => {
      buffer += chunk.toString('utf8')
      const lines = buffer.split(/\r?\n/).filter(Boolean)
      const last = lines[lines.length - 1]
      if (last && /^\d{3} /.test(last)) {
        socket.removeListener('data', onData)
        resolve({ code: Number(last.slice(0, 3)), text: lines.join('\n') })
      }
    }
    socket.on('data', onData)
    socket.once('error', reject)
    setTimeout(() => reject(new Error('the server did not answer within 15s')), 15000)
  })
}

async function say(socket, line, label) {
  socket.write(line + '\r\n')
  const r = await reply(socket)
  console.log(`  ${label.padEnd(12)} ${r.code}  ${r.text.split('\n').pop()}`)
  return r
}

async function main() {
  console.log(`\n  Talking to ${host}:${port}\n`)

  const plain = net.connect({ host, port })
  await new Promise((res, rej) => {
    plain.once('connect', res)
    plain.once('error', rej)
  })

  const greeting = await reply(plain)
  console.log(`  greeting     ${greeting.code}  ${greeting.text.split('\n')[0]}`)

  await say(plain, 'EHLO trustiq.local', 'EHLO')
  const starttls = await say(plain, 'STARTTLS', 'STARTTLS')
  if (starttls.code !== 220) {
    console.error('\n  The server would not upgrade to TLS. Nothing else is worth trying.\n')
    return 1
  }

  const secure = tls.connect({ socket: plain, servername: host })
  await new Promise((res, rej) => {
    secure.once('secureConnect', res)
    secure.once('error', rej)
  })
  console.log(`  TLS          ok   ${secure.getProtocol()}`)

  await say(secure, 'EHLO trustiq.local', 'EHLO')

  // AUTH LOGIN, the form Brevo accepts. The credentials go out base64 encoded
  // as the protocol requires and are never printed here.
  const auth = await say(secure, 'AUTH LOGIN', 'AUTH')
  if (auth.code !== 334) {
    console.error('\n  The server did not offer AUTH LOGIN.\n')
    return 1
  }
  await say(secure, Buffer.from(cfg.SMTP_USER).toString('base64'), 'user')
  const done = await say(secure, Buffer.from(cfg.SMTP_PASS).toString('base64'), 'password')

  secure.write('QUIT\r\n')
  secure.end()

  if (done.code === 235) {
    console.log(`
  Authenticated. The credentials are right and the account may send.

  If Supabase still reports "Error sending confirmation email", the problem
  is the From address rather than the login: it has to be a sender Brevo has
  verified, exactly.
`)
    return 0
  }

  console.error(`
  Refused, and the line above is the server's own explanation.

    535 with "authentication failed"  the login or the key is wrong. The login
                                      is the one on the SMTP page, usually
                                      something@smtp-brevo.com, not your email.
    550 or a mention of activation    the account is not cleared to send yet.
                                      That is Brevo reviewing a new free
                                      account, not our configuration.
`)
  return 1
}

main().then((code) => { process.exitCode = code }, (e) => {
  console.error(`\n  Could not finish: ${e.message}\n`)
  process.exitCode = 1
})
