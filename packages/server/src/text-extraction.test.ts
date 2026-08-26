import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  EXTRACTABLE_CONTENT_TYPES,
  MAX_EXTRACTED_CHARS,
  extractText,
  type Extraction,
  type ExtractionStatus,
} from './text-extraction.js'

const utf8 = (text: string): Uint8Array => new TextEncoder().encode(text)

/**
 * Invisible characters, written as code points on purpose.
 *
 * Pasting the real characters into a test file makes the test unreviewable and
 * unreliable: an editor, a linter or a copy-paste can silently drop them, and
 * the assertion then passes while proving nothing.
 */
const ZERO_WIDTH_SPACE = String.fromCharCode(0x200b)
const LEFT_TO_RIGHT_MARK = String.fromCharCode(0x200e)
const RIGHT_TO_LEFT_OVERRIDE = String.fromCharCode(0x202e)
const POP_DIRECTIONAL = String.fromCharCode(0x202c)
const WORD_JOINER = String.fromCharCode(0x2060)
const BOM = String.fromCharCode(0xfeff)
const BELL = String.fromCharCode(0x07)

function utf16le(text: string, withBom = true): Uint8Array {
  const body = new Uint8Array(text.length * 2 + (withBom ? 2 : 0))
  let at = 0
  if (withBom) {
    body[at++] = 0xff
    body[at++] = 0xfe
  }
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i)
    body[at++] = code & 0xff
    body[at++] = code >> 8
  }
  return body
}

/** Reads the text out of a result, failing the test if there is none. */
function textOf(result: Extraction): string {
  expect(result.text).not.toBeNull()
  return result.text as string
}

describe('extractText', () => {
  describe('what it will and will not read', () => {
    it.each(EXTRACTABLE_CONTENT_TYPES)('reads %s', (contentType) => {
      const result = extractText(utf8('the agreed fee was 500 AED'), contentType)
      expect(result.status).toBe('extracted')
      expect(result.text).toBe('the agreed fee was 500 AED')
    })

    it.each(['application/pdf', 'image/png', 'image/jpeg', 'application/zip'])(
      'reports %s as unsupported rather than failed',
      (contentType) => {
        // The distinction matters downstream: unsupported means there was
        // never anything to read, failed means there was and we could not.
        const result = extractText(utf8('irrelevant'), contentType)
        expect(result).toEqual({ status: 'unsupported', text: null, reason: null })
      },
    )
  })

  describe('encodings', () => {
    it('strips a UTF-8 byte order mark instead of keeping it in the text', () => {
      const bytes = new Uint8Array([0xef, 0xbb, 0xbf, ...utf8('hello')])
      expect(extractText(bytes, 'text/plain').text).toBe('hello')
    })

    it('reads UTF-16 LE, which is what Windows editors still produce', () => {
      const result = extractText(utf16le('Delivered on time.'), 'text/plain')
      expect(result.status).toBe('extracted')
      expect(result.text).toBe('Delivered on time.')
    })

    it('reads UTF-16 BE', () => {
      const le = utf16le('paid in full', false)
      const be = new Uint8Array([0xfe, 0xff, ...swapPairs(le)])
      expect(extractText(be, 'text/plain').text).toBe('paid in full')
    })

    it('keeps Arabic intact', () => {
      const arabic = 'تم تسليم العمل في الموعد المتفق عليه'
      expect(extractText(utf8(arabic), 'text/plain').text).toBe(arabic)
    })

    it('refuses bytes that are not valid UTF-8 rather than guessing an encoding', () => {
      // Latin-1 "café". Decoding this as Latin-1 would work; decoding the same
      // bytes as Latin-1 when they were really UTF-8 turns Arabic into
      // mojibake, so the guess is not worth making either way.
      const latin1 = new Uint8Array([0x63, 0x61, 0x66, 0xe9])
      const result = extractText(latin1, 'text/plain')
      expect(result.status).toBe('failed')
      expect(result.reason).toMatch(/UTF-8/)
    })
  })

  describe('files that are not really text', () => {
    it('fails on a binary file mislabelled as text, rather than storing what survives cleaning', () => {
      // The start of a zip archive, declared as text/plain.
      const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x00, 0x00, 0x41])
      const result = extractText(bytes, 'text/plain')
      expect(result.status).toBe('failed')
      expect(result.reason).toMatch(/null characters/)
      expect(result.text).toBeNull()
    })

    it('fails on a file with nothing but whitespace', () => {
      const result = extractText(utf8('   \n\n\t  \n'), 'text/plain')
      expect(result.status).toBe('failed')
      expect(result.reason).toMatch(/no readable text/)
    })

    it('fails on a file whose only content is invisible', () => {
      // Every character here is dropped, so without the emptiness check the
      // result would be an empty string reported as successfully extracted.
      const invisible = ZERO_WIDTH_SPACE + LEFT_TO_RIGHT_MARK + WORD_JOINER + BOM
      const result = extractText(utf8(invisible), 'text/plain')
      expect(result.status).toBe('failed')
    })
  })

  describe('cleaning', () => {
    it('normalises CRLF and lone CR to newlines', () => {
      const result = extractText(utf8('one\r\ntwo\rthree\nfour'), 'text/plain')
      expect(result.text).toBe('one\ntwo\nthree\nfour')
    })

    it('keeps tabs, because a pasted table loses its columns without them', () => {
      expect(extractText(utf8('item\tprice\nlogo\t500'), 'text/csv').text).toBe(
        'item\tprice\nlogo\t500',
      )
    })

    it('drops control characters', () => {
      const result = extractText(utf8(`before${BELL}after`), 'text/plain')
      expect(result.text).toBe('beforeafter')
    })

    it('drops the invisible characters an instruction could hide in', () => {
      // A reviewer opening this file sees "Pay the seller in full." The model
      // would otherwise also see the override characters around it.
      const sneaky =
        'Pay the seller' + RIGHT_TO_LEFT_OVERRIDE + ' in full' + POP_DIRECTIONAL + '.' + ZERO_WIDTH_SPACE
      const result = extractText(utf8(sneaky), 'text/plain')
      expect(textOf(result)).toBe('Pay the seller in full.')
      for (const hidden of [RIGHT_TO_LEFT_OVERRIDE, POP_DIRECTIONAL, ZERO_WIDTH_SPACE]) {
        expect(textOf(result).includes(hidden)).toBe(false)
      }
    })

    it('leaves ordinary punctuation and emoji alone', () => {
      const text = 'Invoice #12 — paid ✅ (500 AED)'
      expect(extractText(utf8(text), 'text/plain').text).toBe(text)
    })
  })

  describe('the ceiling', () => {
    it('marks a document over the ceiling as truncated', () => {
      const long = 'x'.repeat(MAX_EXTRACTED_CHARS + 1)
      const result = extractText(utf8(long), 'text/plain')
      expect(result.status).toBe('truncated')
      expect(textOf(result).length).toBeLessThanOrEqual(MAX_EXTRACTED_CHARS)
    })

    it('does not mark a document exactly at the ceiling', () => {
      const exact = 'x'.repeat(MAX_EXTRACTED_CHARS)
      const result = extractText(utf8(exact), 'text/plain')
      expect(result.status).toBe('extracted')
      expect(textOf(result)).toHaveLength(MAX_EXTRACTED_CHARS)
    })

    it('cuts on a line boundary when there is one near the ceiling', () => {
      const line = `${'a'.repeat(99)}\n`
      const result = extractText(utf8(line.repeat(1000)), 'text/plain')
      expect(result.status).toBe('truncated')
      // Ending mid-word invites the model to finish the sentence itself.
      expect(textOf(result).endsWith('a')).toBe(true)
      expect(textOf(result).split('\n').every((l) => l.length === 0 || l.length === 99)).toBe(true)
    })

    it('still cuts one enormous line, rather than keeping a fifth of the budget', () => {
      // A break at character 10 is a line boundary, and honouring it would
      // throw away almost everything. The hard cut is the better answer.
      const result = extractText(utf8(`short\nline\n${'y'.repeat(MAX_EXTRACTED_CHARS * 2)}`), 'text/plain')
      expect(textOf(result)).toHaveLength(MAX_EXTRACTED_CHARS)
    })

    it('never puts a truncation marker in the text, because a party could type one', () => {
      const result = extractText(utf8('z'.repeat(MAX_EXTRACTED_CHARS + 500)), 'text/plain')
      expect(textOf(result)).toMatch(/^z+$/)
    })
  })

  it('reports a reason only when it failed', () => {
    const cases: Extraction[] = [
      extractText(utf8('fine'), 'text/plain'),
      extractText(utf8('fine'), 'application/pdf'),
      extractText(utf8('q'.repeat(MAX_EXTRACTED_CHARS + 1)), 'text/plain'),
      extractText(new Uint8Array([0x00]), 'text/plain'),
    ]
    for (const result of cases) {
      expect(result.reason === null).toBe(result.status !== 'failed')
      expect(result.text === null).toBe(result.status === 'unsupported' || result.status === 'failed')
    }
  })
})

/** Turns UTF-16 LE bytes into UTF-16 BE, for the big-endian test. */
function swapPairs(bytes: Uint8Array): Uint8Array {
  const out = new Uint8Array(bytes.length)
  for (let i = 0; i < bytes.length; i += 2) {
    out[i] = bytes[i + 1] as number
    out[i + 1] = bytes[i] as number
  }
  return out
}

/**
 * The ceiling and the status names live in two places: here, and as CHECK
 * constraints in supabase/migrations/0010_evidence_extracted_text.sql. Two
 * copies of a rule is a liability the moment they disagree, so this reads the
 * migration as text and fails if they have drifted. Same guard the state
 * machines get.
 */
describe('parity with the schema', () => {
  const migration = readFileSync(
    new URL('../../../supabase/migrations/0010_evidence_extracted_text.sql', import.meta.url),
    'utf8',
  ).replace(/--[^\n]*/g, '')

  it('caps extracted text at the same length the database does', () => {
    const declared = /length\(extracted_text\)\s*<=\s*(\d+)/.exec(migration)?.[1]
    expect(declared, 'no length check found in migration 0010').toBeDefined()
    expect(Number(declared)).toBe(MAX_EXTRACTED_CHARS)
  })

  it('uses exactly the statuses the database allows', () => {
    const listed = /extraction_status in \(([^)]*)\)/.exec(migration)?.[1]
    expect(listed, 'no status check found in migration 0010').toBeDefined()
    const inSql = [...(listed as string).matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort()

    // `not_attempted` exists only in the database, for rows filed before
    // extraction did. Nothing in this package can produce it.
    const produced: ExtractionStatus[] = ['unsupported', 'failed', 'extracted', 'truncated']
    expect(inSql).toEqual([...produced, 'not_attempted'].sort())
  })
})
