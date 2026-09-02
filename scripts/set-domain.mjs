/**
 * Moves the site from the GitHub Pages URL to a domain of its own.
 *
 *   node scripts/set-domain.mjs trustiq.com --dry
 *   node scripts/set-domain.mjs trustiq.com
 *
 * A domain change is not a DNS record. The project is served from a
 * subdirectory today, so `base` is `/trustiq-uae/` and that prefix is written
 * into every asset path, every internal link, both canonical URLs, the sitemap,
 * the app's kill-switch URL, and the two legal pages the Play listing points
 * at. Ninety-seven places at the time this was written. Doing it by hand means
 * finding ninety-six of them.
 *
 * What this does NOT do, because neither can be done from here:
 *
 *   - the DNS records at your registrar;
 *   - the Supabase auth site_url and redirect allow list, which is
 *     `node scripts/configure-auth.mjs --apply` once TRUSTIQ_SITE_URL is set.
 *
 * It prints both at the end rather than leaving you to remember them.
 *
 * Reversible: `git checkout .` before committing, or run it again with the old
 * host. Nothing here touches the database.
 */

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const OLD_HOST = 'mtieze.github.io'
const OLD_BASE = '/trustiq-uae/'

const args = process.argv.slice(2)
const dry = args.includes('--dry')
const host = args.find((a) => !a.startsWith('--'))

if (!host) {
  console.error(`
  A hostname is needed.

    node scripts/set-domain.mjs trustiq.com --dry
    node scripts/set-domain.mjs trustiq.com

  Bare hostname, no scheme and no trailing slash. Use the apex you actually
  want people to type; www is a redirect you set at the registrar, not a
  second site.
`)
  process.exit(1)
}

if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(host)) {
  console.error(`\n  "${host}" does not look like a hostname.\n`)
  process.exit(1)
}

/**
 * Every file that mentions either, found rather than listed.
 *
 * This was a hand-written list of twenty-five paths first. A list is the way
 * to miss the twenty-sixth: it was already missing four pages that turned out
 * not to need changing, which is luck rather than correctness.
 */
function candidates(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) {
      if (SKIP.has(entry.name)) continue
      candidates(path, out)
    } else if (KEEP.test(entry.name)) {
      out.push(path)
    }
  }
  return out
}

const SKIP = new Set(['node_modules', 'dist', '.git', '.dart_tool', 'build', '_shared', 'goldens', 'screens'])
const KEEP = /\.(html|jsx?|tsx?|dart|xml|txt|json|yml|yaml|md|css)$/i

const FILES = candidates('apps').concat(candidates('supabase'))

let changed = 0
let touched = 0

for (const file of FILES) {
  if (!existsSync(file)) continue
  const before = readFileSync(file, 'utf8')
  let after = before

  // The absolute URL first, so the path rewrite below does not chew through a
  // host it has already handled.
  after = after.split(`https://${OLD_HOST}${OLD_BASE}`).join(`https://${host}/`)
  after = after.split(`https://${OLD_HOST}/trustiq-uae`).join(`https://${host}`)

  // Then the bare path prefix: /trustiq-uae/foo -> /foo.
  after = after.split(OLD_BASE).join('/')

  if (after !== before) {
    const hits = (before.match(new RegExp(OLD_HOST.replace(/\./g, '\\.'), 'g')) ?? []).length +
      (before.split(OLD_BASE).length - 1)
    changed += hits
    touched += 1
    console.log(`  ${String(hits).padStart(3)}  ${file}`)
    if (!dry) writeFileSync(file, after)
  }
}

// The file GitHub Pages reads to know the site answers on another name. One
// line, no scheme. Without it the custom domain 404s and nothing says why.
const cname = join('apps', 'web', 'public', 'CNAME')
if (!dry) writeFileSync(cname, host + '\n')
console.log(`  ${String(1).padStart(3)}  ${cname}${dry ? ' (would be written)' : ''}`)

console.log(`\n${dry ? 'Would rewrite' : 'Rewrote'} ${changed} reference(s) across ${touched} file(s).\n`)

console.log(`Two things this cannot do for you.

  1. DNS, at your registrar. For an apex like ${host}, four A records:

       185.199.108.153
       185.199.109.153
       185.199.110.153
       185.199.111.153

     and a CNAME for www pointing at mtieze.github.io. Confirm the current
     addresses in GitHub's own docs before you type them: they have changed
     before and this comment will not have.

     Then in the repository settings, Pages, set the custom domain to
     ${host} and wait for the certificate. Turn on Enforce HTTPS once it
     appears, not before.

  2. Supabase auth, or every confirmation email keeps pointing at the old
     host. Put this in .env and apply it:

       TRUSTIQ_SITE_URL=https://${host}/confirmed.html
       TRUSTIQ_REDIRECT_URLS=https://${host}/**

       node scripts/configure-auth.mjs --show
       node scripts/configure-auth.mjs --apply

One thing to know rather than do. Any copy of the app already installed polls
the old status.json URL. GitHub redirects the old address to the new one and
the http package follows redirects, so those builds keep working; the default
in config.dart is updated for every build made from here on.
`)
