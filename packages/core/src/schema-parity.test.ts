/**
 * Drift guard between the TypeScript domain and the SQL schema.
 *
 * The state machines exist twice on purpose: in TypeScript so the apps can
 * reason about them offline, and in Postgres so no client can talk the database
 * into an illegal move. Two copies of a rule is a liability the moment they
 * disagree, so this suite parses the migrations and fails if they do.
 *
 * It reads SQL as text rather than connecting to a database, so it runs in CI
 * with no Docker and no Supabase.
 */

import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { TRANSITIONS } from './transaction-machine.js'
import { DISPUTE_TRANSITIONS } from './dispute-machine.js'
import { RESOLUTION_DECISIONS } from './resolution.js'
import {
  DISPUTE_EVENTS,
  DISPUTE_STATES,
  TERMINAL_DISPUTE_STATES,
  TERMINAL_TRANSACTION_STATES,
  TRANSACTION_EVENTS,
  TRANSACTION_STATES,
} from './types.js'

function migration(name: string): string {
  const url = new URL(`../../../supabase/migrations/${name}`, import.meta.url)
  // Strip SQL line comments before parsing: several of them mention future
  // state names in quotes, which would otherwise be read as real enum members.
  return readFileSync(url, 'utf8').replace(/--[^\n]*/g, '')
}

const FOUNDATION = migration('0001_foundation.sql')
const TRANSACTIONS_SQL = migration('0003_transactions.sql')
const DISPUTES_SQL = migration('0005_disputes.sql')

function parseEnum(sql: string, name: string): string[] {
  const match = new RegExp(
    `create\\s+type\\s+public\\.${name}\\s+as\\s+enum\\s*\\(([\\s\\S]*?)\\)\\s*;`,
    'i',
  ).exec(sql)
  if (match?.[1] === undefined) throw new Error(`enum public.${name} not found in migration`)
  return [...match[1].matchAll(/'([^']+)'/g)].map((m) => m[1] as string)
}

interface SqlTransition {
  from: string
  event: string
  to: string
  actors: string[]
}

function parseTransitions(sql: string, table: string): SqlTransition[] {
  const block = new RegExp(
    `insert\\s+into\\s+app\\.${table}\\s*\\([^)]*\\)\\s*values([\\s\\S]*?);`,
    'i',
  ).exec(sql)
  if (block?.[1] === undefined) throw new Error(`seed rows for app.${table} not found`)

  const rows = [
    ...block[1].matchAll(
      /\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'\{([^}]*)\}'/g,
    ),
  ]
  return rows.map((m) => ({
    from: m[1] as string,
    event: m[2] as string,
    to: m[3] as string,
    actors: (m[4] as string).split(',').map((a) => a.trim()).filter(Boolean),
  }))
}

/** Comparable, order-independent key for one transition. */
function key(t: { from: string; event: string; to: string; actors: readonly string[] }): string {
  return `${t.from} --${t.event}--> ${t.to} [${[...t.actors].sort().join('|')}]`
}

describe('enum parity', () => {
  const cases: [string, readonly string[]][] = [
    ['transaction_state', TRANSACTION_STATES],
    ['transaction_event', TRANSACTION_EVENTS],
    ['dispute_state', DISPUTE_STATES],
    ['dispute_event', DISPUTE_EVENTS],
    ['resolution_decision', RESOLUTION_DECISIONS],
  ]

  for (const [enumName, tsValues] of cases) {
    it(`public.${enumName} matches its TypeScript union, in the same order`, () => {
      expect(parseEnum(FOUNDATION, enumName)).toEqual([...tsValues])
    })
  }

  it('party_role and actor_role match the TypeScript roles', () => {
    expect(parseEnum(FOUNDATION, 'party_role')).toEqual(['buyer', 'seller'])
    expect(parseEnum(FOUNDATION, 'actor_role')).toEqual(['buyer', 'seller', 'system'])
  })
})

describe('transaction transition parity', () => {
  const sqlRows = parseTransitions(TRANSACTIONS_SQL, 'transaction_transitions')

  it('seeds the same number of rules as the TypeScript table', () => {
    expect(sqlRows).toHaveLength(TRANSITIONS.length)
  })

  it('seeds exactly the same rules, actors included', () => {
    expect(new Set(sqlRows.map(key))).toEqual(new Set(TRANSITIONS.map(key)))
  })

  it('never seeds a rule leaving a state TypeScript treats as terminal', () => {
    for (const terminal of TERMINAL_TRANSACTION_STATES) {
      expect(
        sqlRows.filter((r) => r.from === terminal),
        `SQL lets ${terminal} transition out, but TypeScript calls it terminal`,
      ).toHaveLength(0)
    }
  })

  it('only references states and events the enums declare', () => {
    const states = new Set(parseEnum(FOUNDATION, 'transaction_state'))
    const events = new Set(parseEnum(FOUNDATION, 'transaction_event'))
    for (const row of sqlRows) {
      expect(states.has(row.from), `unknown from_state ${row.from}`).toBe(true)
      expect(states.has(row.to), `unknown to_state ${row.to}`).toBe(true)
      expect(events.has(row.event), `unknown event ${row.event}`).toBe(true)
    }
  })
})

describe('dispute transition parity', () => {
  const sqlRows = parseTransitions(DISPUTES_SQL, 'dispute_transitions')

  it('seeds the same number of rules as the TypeScript table', () => {
    expect(sqlRows).toHaveLength(DISPUTE_TRANSITIONS.length)
  })

  it('seeds exactly the same rules, actors included', () => {
    expect(new Set(sqlRows.map(key))).toEqual(new Set(DISPUTE_TRANSITIONS.map(key)))
  })

  it('never seeds a rule leaving a state TypeScript treats as terminal', () => {
    for (const terminal of TERMINAL_DISPUTE_STATES) {
      expect(
        sqlRows.filter((r) => r.from === terminal),
        `SQL lets ${terminal} transition out, but TypeScript calls it terminal`,
      ).toHaveLength(0)
    }
  })

  it('keeps accept_proposal reserved for the system on both sides', () => {
    // If a party could fire this directly, one side could close a dispute alone.
    const sqlRule = sqlRows.find((r) => r.event === 'accept_proposal')
    expect(sqlRule?.actors).toEqual(['system'])
    const tsRule = DISPUTE_TRANSITIONS.find((r) => r.event === 'accept_proposal')
    expect(tsRule?.actors).toEqual(['system'])
  })
})

describe('money parity', () => {
  it('uses the same ceiling in the fils domain as in TypeScript', () => {
    // MAX_FILS in money.ts is 9_223_372_036_854.
    expect(FOUNDATION).toMatch(/between\s+-9223372036854\s+and\s+9223372036854/)
  })
})
