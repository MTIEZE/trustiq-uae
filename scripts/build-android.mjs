/**
 * Builds the Android app for the closed beta.
 *
 *   node scripts/build-android.mjs            release, one APK for every phone
 *   node scripts/build-android.mjs --bundle   an .aab, which is what Play takes
 *   node scripts/build-android.mjs --split    one APK per architecture, smaller
 *   node scripts/build-android.mjs --debug    no keystore needed, for a quick look
 *
 * APK by default, because that is what you send a tester over WhatsApp. Play
 * has not accepted an APK since 2021 and needs the bundle, which nobody can
 * install directly: it is a set of parts Play assembles per device and signs
 * with its own key.
 *
 * The project is bound to a Supabase project at build time, not at runtime, so
 * the URL and the publishable key have to be passed in. Reading them from .env
 * here means nobody has to remember a forty-character flag, and nobody pastes a
 * key into a shell history.
 *
 * It refuses to build with a service-role key. The app checks for one at
 * startup too, but by then the key is already inside an APK on somebody's
 * phone. A key that ships cannot be unshipped: it can only be rotated, and
 * every copy of that build stays broken afterwards. This is the cheaper place
 * to find out.
 */

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const MOBILE = 'apps/mobile'
const OUT = join(MOBILE, 'build/app/outputs/flutter-apk')
const BUNDLE_OUT = join(MOBILE, 'build/app/outputs/bundle/release')

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

/// Says why a key looks like a service-role key, or null if it does not.
/// The same two checks as TrustIqConfig.describeServiceRoleKey in the app,
/// because both key formats are in circulation.
function describeServiceRoleKey(key) {
  if (key.startsWith('sb_secret_')) return 'it starts with sb_secret_'
  const parts = key.split('.')
  if (parts.length === 3) {
    try {
      const payload = Buffer.from(
        parts[1].replace(/-/g, '+').replace(/_/g, '/'),
        'base64',
      ).toString('utf8')
      if (payload.includes('"service_role"')) return 'its JWT payload names the service_role'
    } catch {
      // Not decodable is not evidence of anything.
    }
  }
  return null
}

function mb(path) {
  return (statSync(path).size / 1024 / 1024).toFixed(1) + ' MB'
}

function main() {
  const cfg = env()
  const debug = process.argv.includes('--debug')
  const split = process.argv.includes('--split')
  const bundle = process.argv.includes('--bundle')

  if (bundle && split) {
    console.error(`
  --bundle and --split do not go together. Splitting per architecture is what
  Play does with a bundle on its own, so asking for both is asking Flutter to
  do by hand the one thing the bundle exists to avoid.
`)
    return 1
  }
  if (bundle && debug) {
    console.error('\n  A debug bundle is of no use to anybody. Drop one of the two.\n')
    return 1
  }

  for (const k of ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (!cfg[k]) {
      console.error(`\n  ${k} is not set in .env\n`)
      return 1
    }
  }

  const complaint = describeServiceRoleKey(cfg.SUPABASE_ANON_KEY)
  if (complaint) {
    console.error(`
  SUPABASE_ANON_KEY looks like a service-role key (${complaint}).

  That key bypasses row level security completely. In an APK it is readable
  by anyone who downloads the app, and it grants read and write access to
  every contract, dispute and document belonging to every user.

  Nothing was built. Use the publishable key.
`)
    return 1
  }

  if (!debug && !existsSync(join(MOBILE, 'android/key.properties'))) {
    console.error(`
  No android/key.properties, so the release build would be unsigned.

  Create a keystore once, and keep it. Losing it means never being able to
  update the app on Play under the same identity:

    keytool -genkey -v -keystore ~/trustiq-upload.jks -keyalg RSA \\
            -keysize 2048 -validity 10000 -alias upload

  Then write ${MOBILE}/android/key.properties (already gitignored):

    storeFile=C:/Users/you/trustiq-upload.jks
    storePassword=...
    keyAlias=upload
    keyPassword=...

  Or pass --debug for a build you can install and look at, but not ship.
`)
    return 1
  }

  const args = [
    'build',
    bundle ? 'appbundle' : 'apk',
    debug ? '--debug' : '--release',
    `--dart-define=SUPABASE_URL=${cfg.SUPABASE_URL}`,
    `--dart-define=SUPABASE_ANON_KEY=${cfg.SUPABASE_ANON_KEY}`,
  ]
  if (cfg.TRUSTIQ_VERIFY_CONTACT) {
    args.push(`--dart-define=TRUSTIQ_VERIFY_CONTACT=${cfg.TRUSTIQ_VERIFY_CONTACT}`)
  }
  // One APK that installs on any phone, unless asked otherwise. Three files
  // are smaller each but somebody has to know which one to send.
  if (split) args.push('--split-per-abi')

  console.log(`\n  Building against ${new URL(cfg.SUPABASE_URL).host}\n`)

  try {
    // Inherited stdio: Gradle's own output is the useful part when this fails.
    execFileSync('flutter', args, { cwd: MOBILE, stdio: 'inherit', shell: true })
  } catch {
    console.error('\n  The build failed. The Gradle output above says why.\n')
    return 1
  }

  const built = bundle
    ? ['app-release.aab']
    : split
      ? ['app-armeabi-v7a-release.apk', 'app-arm64-v8a-release.apk', 'app-x86_64-release.apk']
      : [debug ? 'app-debug.apk' : 'app-release.apk']

  console.log('')
  let found = 0
  for (const name of built) {
    const path = join(bundle ? BUNDLE_OUT : OUT, name)
    if (existsSync(path)) {
      found += 1
      console.log(`  ${path}  ${mb(path)}`)
    }
  }
  if (found === 0) {
    console.error(`  The build reported success but produced no ${bundle ? 'bundle' : 'APK'}.`)
    return 1
  }
  if (bundle) {
    console.log(`
  This cannot be installed on a phone. Upload it to Play Console; Play builds
  the per-device APK from it and signs that with its own key.
`)
  }
  console.log('')
  return 0
}

process.exitCode = main()
