/**
 * Drift guard between the TypeScript domain and the Dart port.
 *
 * The rules now exist three times: TypeScript here, SQL in the migrations, and
 * Dart in `packages/core-dart` for the Flutter app. Three copies is two chances
 * to disagree. `schema-parity.test.ts` covers TypeScript against SQL; this file
 * covers TypeScript against Dart, so every pair is pinned.
 *
 * It parses the Dart source as text, so it runs in CI with no Dart SDK.
 *
 * Dart enum members are camelCase while the wire values are snake_case, so the
 * comparison goes through each member's declared wire name. That is deliberate:
 * the wire value is what actually crosses into the database and the API, and it
 * is the thing that must not drift.
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

function dartSource(name: string): string {
  const url = new URL(`../../core-dart/lib/src/${name}`, import.meta.url)
  // Strip line comments: several mention future state names that would
  // otherwise be read as real members.
  return readFileSync(url, 'utf8').replace(/\/\/[^\n]*/g, '')
}

const TYPES = dartSource('types.dart')
const TRANSACTIONS_DART = dartSource('transaction_machine.dart')
const DISPUTES_DART = dartSource('dispute_machine.dart')

/**
 * Maps a Dart enum's member names to their wire names.
 *
 * `pendingAcceptance('pending_acceptance')` -> pendingAcceptance : pending_acceptance
 * `active`                                  -> active            : active
 */
function parseDartEnum(name: string): Map<string, string> {
  const block = new RegExp(`enum\\s+${name}\\s*\\{([\\s\\S]*?);`).exec(TYPES)
  if (block?.[1] === undefined) throw new Error(`Dart enum ${name} not found`)

  const members = new Map<string, string>()
  for (const line of block[1].split(',')) {
    const match = /^\s*([A-Za-z_]\w*)\s*(?:\(\s*'([^']+)'\s*\))?\s*$/.exec(line)
    if (match?.[1] === undefined) continue
    members.set(match[1], match[2] ?? match[1])
  }
  if (members.size === 0) throw new Error(`Dart enum ${name} parsed as empty`)
  return members
}

const transactionStates = parseDartEnum('TransactionState')
const transactionEvents = parseDartEnum('TransactionEvent')
const disputeStates = parseDartEnum('DisputeState')
const disputeEvents = parseDartEnum('DisputeEvent')
const actorRoles = parseDartEnum('Actor')

function wire(members: Map<string, string>, member: string): string {
  const value = members.get(member)
  if (value === undefined) throw new Error(`unknown Dart member ${member}`)
  return value
}

interface DartTransition {
  from: string
  event: string
  to: string
  actors: string[]
}

function parseDartTransitions(
  source: string,
  ruleType: string,
  stateEnum: string,
  eventEnum: string,
  states: Map<string, string>,
  events: Map<string, string>,
): DartTransition[] {
  const pattern = new RegExp(
    `${ruleType}\\(\\s*` +
      `from:\\s*${stateEnum}\\.(\\w+),\\s*` +
      `event:\\s*${eventEnum}\\.(\\w+),\\s*` +
      `to:\\s*${stateEnum}\\.(\\w+),\\s*` +
      `actors:\\s*\\{([^}]*)\\}`,
    'g',
  )
  return [...source.matchAll(pattern)].map((m) => ({
    from: wire(states, m[1] as string),
    event: wire(events, m[2] as string),
    to: wire(states, m[3] as string),
    actors: [...(m[4] as string).matchAll(/Actor\.(\w+)/g)].map((a) =>
      wire(actorRoles, a[1] as string),
    ),
  }))
}

/** Comparable, order-independent key for one transition. */
function key(t: { from: string; event: string; to: string; actors: readonly string[] }): string {
  return `${t.from} --${t.event}--> ${t.to} [${[...t.actors].sort().join('|')}]`
}

describe('Dart enum parity', () => {
  const cases: [string, Map<string, string>, readonly string[]][] = [
    ['TransactionState', transactionStates, TRANSACTION_STATES],
    ['TransactionEvent', transactionEvents, TRANSACTION_EVENTS],
    ['DisputeState', disputeStates, DISPUTE_STATES],
    ['DisputeEvent', disputeEvents, DISPUTE_EVENTS],
  ]

  for (const [name, members, tsValues] of cases) {
    it(`${name} declares the same wire values as TypeScript, in the same order`, () => {
      expect([...members.values()]).toEqual([...tsValues])
    })
  }

  it('Role and Actor match the TypeScript roles', () => {
    expect([...parseDartEnum('Role').values()]).toEqual(['buyer', 'seller'])
    expect([...actorRoles.values()]).toEqual(['buyer', 'seller', 'system'])
  })

  it('ResolutionDecision matches the TypeScript decisions', () => {
    expect([...parseDartEnum('ResolutionDecision').values()]).toEqual([...RESOLUTION_DECISIONS])
  })

  it('marks the same transaction states terminal on both sides', () => {
    const block = /bool get isTerminal => const \{([\s\S]*?)\}/.exec(
      TYPES.slice(TYPES.indexOf('enum TransactionState')),
    )
    const dartTerminal = [...(block?.[1] ?? '').matchAll(/TransactionState\.(\w+)/g)].map((m) =>
      wire(transactionStates, m[1] as string),
    )
    expect(new Set(dartTerminal)).toEqual(new Set(TERMINAL_TRANSACTION_STATES))
  })

  it('marks the same dispute states terminal on both sides', () => {
    const block = /bool get isTerminal => const \{([\s\S]*?)\}/.exec(
      TYPES.slice(TYPES.indexOf('enum DisputeState')),
    )
    const dartTerminal = [...(block?.[1] ?? '').matchAll(/DisputeState\.(\w+)/g)].map((m) =>
      wire(disputeStates, m[1] as string),
    )
    expect(new Set(dartTerminal)).toEqual(new Set(TERMINAL_DISPUTE_STATES))
  })
})

describe('Dart transaction transition parity', () => {
  const dartRows = parseDartTransitions(
    TRANSACTIONS_DART,
    'TransitionRule',
    'TransactionState',
    'TransactionEvent',
    transactionStates,
    transactionEvents,
  )

  it('declares the same number of rules as TypeScript', () => {
    expect(dartRows).toHaveLength(TRANSITIONS.length)
  })

  it('declares exactly the same rules, actors included', () => {
    expect(new Set(dartRows.map(key))).toEqual(new Set(TRANSITIONS.map(key)))
  })

  it('never declares a rule leaving a terminal state', () => {
    for (const terminal of TERMINAL_TRANSACTION_STATES) {
      expect(
        dartRows.filter((r) => r.from === terminal),
        `Dart lets ${terminal} transition out`,
      ).toHaveLength(0)
    }
  })
})

describe('Dart dispute transition parity', () => {
  const dartRows = parseDartTransitions(
    DISPUTES_DART,
    'DisputeTransitionRule',
    'DisputeState',
    'DisputeEvent',
    disputeStates,
    disputeEvents,
  )

  it('declares the same number of rules as TypeScript', () => {
    expect(dartRows).toHaveLength(DISPUTE_TRANSITIONS.length)
  })

  it('declares exactly the same rules, actors included', () => {
    expect(new Set(dartRows.map(key))).toEqual(new Set(DISPUTE_TRANSITIONS.map(key)))
  })

  it('keeps accept_proposal reserved for the system in Dart too', () => {
    // If a party could fire this from the app, one side could close a dispute
    // alone. The rule has to hold in every copy, not just the server ones.
    const rule = dartRows.find((r) => r.event === 'accept_proposal')
    expect(rule?.actors).toEqual(['system'])
  })
})

describe('Dart money parity', () => {
  const MONEY = dartSource('money.dart')

  it('uses the same fils ceiling as TypeScript', () => {
    // MAX_FILS in money.ts is 9_223_372_036_854.
    expect(MONEY).toMatch(/maxFils\s*=\s*9223372036854/)
  })

  it('uses the same minor unit', () => {
    expect(MONEY).toMatch(/filsPerAed\s*=\s*100/)
  })

  it('rejects more than two decimals with the same pattern', () => {
    expect(MONEY).toContain(String.raw`^(-)?(\d+)(?:\.(\d{1,2}))?$`)
  })
})
