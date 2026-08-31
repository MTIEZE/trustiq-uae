import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

/**
 * supabase/ROLES.md, held against the migrations that decide it.
 *
 * The roles were correct and undocumented: three separate lists and a flag on a
 * profile, each right on its own, with nothing describing the whole. A document
 * fixes that for exactly as long as somebody keeps it up, which is why this
 * reads both and refuses to let them disagree.
 *
 * Text against text, like schema-parity next door. No database: the point is to
 * fail on a pull request, before anything reaches one.
 */

const ROOT = join(import.meta.dirname, '..', '..', '..')
const MIGRATIONS = join(ROOT, 'supabase', 'migrations')

function migrations(): string {
  return readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .join('\n')
}

/** Every function this project puts in `public`, by name. */
function declared(sql: string): Set<string> {
  const out = new Set<string>()
  for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(/gi)) {
    out.add(m[1])
  }
  return out
}

/**
 * Whether `authenticated` is left holding EXECUTE, read the way Postgres would:
 * statements in order, last one wins.
 *
 * Supabase grants EXECUTE to anon and authenticated on every new function in
 * `public` by default, which is the whole reason every migration here writes an
 * explicit revoke. So the starting position is granted, not denied.
 */
function grantedToAuthenticated(sql: string, name: string): boolean {
  let granted = true
  const pattern = new RegExp(
    `(grant|revoke)\\s+(?:all|execute)(?:\\s+privileges)?\\s+on\\s+function\\s+public\\.${name}\\s*\\(([^)]*)\\)\\s*(?:to|from)\\s+([^;]+);`,
    'gi',
  )
  for (const m of sql.matchAll(pattern)) {
    const roles = m[3].toLowerCase()
    if (!roles.includes('authenticated')) continue
    granted = m[1].toLowerCase() === 'grant'
  }
  return granted
}

/** The last table in ROLES.md: function name to what the document claims. */
function documented(): Map<string, string> {
  const doc = readFileSync(join(ROOT, 'supabase', 'ROLES.md'), 'utf8')
  const out = new Map<string, string>()
  for (const m of doc.matchAll(/^\|\s*`(\w+)\([^)]*\)`\s*\|\s*([^|]+?)\s*\|\s*$/gm)) {
    out.set(m[1], m[2])
  }
  return out
}

describe('the roles document says what the migrations do', () => {
  const sql = migrations()
  const ours = declared(sql)
  const claims = documented()

  it('there is a table to check', () => {
    expect(claims.size).toBeGreaterThan(20)
  })

  it('every function is documented', () => {
    // The failure this is really for: somebody adds a function, grants it to
    // authenticated, and nothing anywhere says it now exists.
    const missing = [...ours].filter((name) => !claims.has(name)).sort()
    expect(missing, `add these to supabase/ROLES.md: ${missing.join(', ')}`).toEqual([])
  })

  it('nothing is documented that does not exist', () => {
    const ghosts = [...claims.keys()].filter((name) => !ours.has(name)).sort()
    expect(ghosts, `these are in ROLES.md and nowhere else: ${ghosts.join(', ')}`).toEqual([])
  })

  it('each claim matches the grants', () => {
    const wrong: string[] = []
    for (const [name, claim] of claims) {
      if (!ours.has(name)) continue
      const granted = grantedToAuthenticated(sql, name)
      const says = claim === 'signed in'
      if (granted !== says) {
        wrong.push(`${name}: document says "${claim}", migrations say ${granted ? 'signed in' : 'system only'}`)
      }
    }
    expect(wrong, wrong.join('\n')).toEqual([])
  })

  it('and the document knows what it is claiming', () => {
    const odd = [...claims.values()].filter((v) => v !== 'signed in' && v !== 'system only')
    expect([...new Set(odd)]).toEqual([])
  })
})
