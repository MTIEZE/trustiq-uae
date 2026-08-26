import { describe, expect, it } from 'vitest'
import { MAX_FILS, filsFromAed } from '@trustiq/core'
import {
  RowMappingError,
  readFils,
  readMilestoneTimes,
  readRole,
  toEvidenceSummary,
  type EvidenceRow,
  type TransactionEventRow,
} from './rows.js'
import { readConnectionFromEnv } from './client.js'

describe('reading a fils column', () => {
  it('accepts the JSON number PostgREST usually returns', () => {
    expect(readFils(50_000, 'x')).toBe(50_000)
  })

  it('accepts the string form, which bigint can also arrive as', () => {
    // Which one you get depends on the value, not the column, so both have to
    // work or an amount will fail to parse on the day it gets large enough.
    expect(readFils('50000', 'x')).toBe(50_000)
    expect(readFils(String(MAX_FILS), 'x')).toBe(MAX_FILS)
  })

  it('handles a negative amount', () => {
    expect(readFils('-1234', 'x')).toBe(-1234)
  })

  it('refuses null rather than turning it into zero', () => {
    // Number(null) is 0. A zero that should have been an error is exactly the
    // kind of thing that reaches a ledger and is never noticed.
    expect(() => readFils(null, 'disputes.disputed_amount_fils')).toThrow(RowMappingError)
    expect(() => readFils(undefined, 'x')).toThrow(RowMappingError)
  })

  it('refuses a value that is not a whole number', () => {
    expect(() => readFils(500.5, 'x')).toThrow(RowMappingError)
    expect(() => readFils('500.5', 'x')).toThrow(RowMappingError)
  })

  it('refuses anything outside the safe integer range', () => {
    expect(() => readFils('99999999999999999999', 'x')).toThrow(RowMappingError)
  })

  it('refuses text and objects', () => {
    for (const bad of ['', 'abc', {}, [], true]) {
      expect(() => readFils(bad, 'x'), JSON.stringify(bad)).toThrow(RowMappingError)
    }
  })

  it('names the column in the message, so a failure is traceable', () => {
    expect(() => readFils(null, 'disputes.disputed_amount_fils')).toThrow(
      /disputes\.disputed_amount_fils/,
    )
  })

  it('round-trips an amount produced by the domain', () => {
    const amount = filsFromAed('500.55')
    expect(readFils(amount, 'x')).toBe(amount)
    expect(readFils(String(amount), 'x')).toBe(amount)
  })
})

describe('reading a role', () => {
  it('accepts the two the enum declares', () => {
    expect(readRole('buyer', 'x')).toBe('buyer')
    expect(readRole('seller', 'x')).toBe('seller')
  })

  it('refuses anything else, including system', () => {
    // `system` is an actor, never a party on a row.
    for (const bad of ['system', 'BUYER', '', null, 3]) {
      expect(() => readRole(bad, 'x'), String(bad)).toThrow(RowMappingError)
    }
  })
})

describe('mapping an evidence row', () => {
  const row: EvidenceRow = {
    id: 'ev_1',
    transaction_id: 'txn_1',
    uploaded_by: 'usr_1',
    uploaded_by_role: 'buyer',
    storage_path: 'txn_1/2026-08-19-abc',
    filename: 'brief.pdf',
    content_type: 'application/pdf',
    byte_size: 1234,
    sha256: 'a'.repeat(64),
    note: 'The brief we agreed on.',
    uploaded_at: '2026-08-19T10:00:00.000Z',
    extracted_text: null,
    extraction_status: 'unsupported',
  }

  it('carries the digest through untouched', () => {
    expect(toEvidenceSummary(row).sha256).toBe('a'.repeat(64));
  })

  it('does not invent extracted text', () => {
    // Extraction happens at upload, not at read. Filling this in here would
    // put words in front of the model that no document actually contains.
    expect(toEvidenceSummary(row).extractedText).toBeNull()
  })

  it('keeps a missing note as null rather than an empty string', () => {
    expect(toEvidenceSummary({ ...row, note: null }).note).toBeNull()
  })

  it('refuses a row whose role column is wrong', () => {
    expect(() => toEvidenceSummary({ ...row, uploaded_by_role: 'system' })).toThrow(
      RowMappingError,
    )
  })
})

describe('reading milestone times from the event log', () => {
  function event(name: string, at: string): TransactionEventRow {
    return { event: name, to_state: 'x', occurred_at: at }
  }

  it('finds the acceptance and the delivery', () => {
    const times = readMilestoneTimes([
      event('submit', '2026-06-01T09:00:00Z'),
      event('accept', '2026-06-01T14:00:00Z'),
      event('mark_delivered', '2026-06-08T10:00:00Z'),
    ])
    expect(times.acceptedAt).toBe('2026-06-01T14:00:00Z')
    expect(times.deliveredAt).toBe('2026-06-08T10:00:00Z')
  })

  it('reports nothing for a contract that never got there', () => {
    const times = readMilestoneTimes([event('submit', '2026-06-01T09:00:00Z')])
    expect(times.acceptedAt).toBeNull()
    expect(times.deliveredAt).toBeNull()
  })

  it('clears the delivery when the work was sent back', () => {
    // A contract can be delivered, revised and delivered again. Reporting the
    // first delivery would tell the model the work was late or early by the
    // wrong number of days.
    const times = readMilestoneTimes([
      event('accept', '2026-06-01T14:00:00Z'),
      event('mark_delivered', '2026-06-08T10:00:00Z'),
      event('request_revision', '2026-06-09T10:00:00Z'),
    ])
    expect(times.deliveredAt).toBeNull()
  })

  it('reports the latest delivery after a revision round', () => {
    const times = readMilestoneTimes([
      event('accept', '2026-06-01T14:00:00Z'),
      event('mark_delivered', '2026-06-08T10:00:00Z'),
      event('request_revision', '2026-06-09T10:00:00Z'),
      event('mark_delivered', '2026-06-12T16:00:00Z'),
    ])
    expect(times.deliveredAt).toBe('2026-06-12T16:00:00Z')
  })

  it('keeps the first acceptance, not a later one', () => {
    // Acceptance is what made the contract binding; it happens once.
    const times = readMilestoneTimes([
      event('accept', '2026-06-01T14:00:00Z'),
      event('accept', '2026-06-05T14:00:00Z'),
    ])
    expect(times.acceptedAt).toBe('2026-06-01T14:00:00Z')
  })
})

describe('reading the connection from the environment', () => {
  it('reads both values when they are set', () => {
    const connection = readConnectionFromEnv({
      SUPABASE_URL: 'https://example.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY: 'a-key',
    })
    expect(connection.url).toBe('https://example.supabase.co')
    expect(connection.serviceRoleKey).toBe('a-key')
  })

  it('says which one is missing rather than failing later', () => {
    expect(() => readConnectionFromEnv({ SUPABASE_URL: 'https://x' })).toThrow(
      /SUPABASE_SERVICE_ROLE_KEY/,
    )
    expect(() => readConnectionFromEnv({ SUPABASE_SERVICE_ROLE_KEY: 'k' })).toThrow(
      /SUPABASE_URL/,
    )
    expect(() => readConnectionFromEnv({})).toThrow(/SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY/)
  })

  it('treats an empty string as missing', () => {
    // An unset variable and one set to nothing are the same mistake, and the
    // second is the one that produces a confusing 401 much later.
    expect(() => readConnectionFromEnv({ SUPABASE_URL: '', SUPABASE_SERVICE_ROLE_KEY: 'k' })).toThrow(
      /SUPABASE_URL/,
    )
  })
})
