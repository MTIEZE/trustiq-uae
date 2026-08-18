import { describe, expect, it } from 'vitest'
import {
  MoneyError,
  ZERO,
  add,
  aedFromFils,
  allocate,
  fils,
  filsFromAed,
  formatAed,
  splitByPercent,
  subtract,
  sum,
} from './money.js'

describe('filsFromAed', () => {
  it('parses whole and fractional amounts exactly', () => {
    expect(filsFromAed('500')).toBe(50_000)
    expect(filsFromAed('500.5')).toBe(50_050)
    expect(filsFromAed('500.55')).toBe(50_055)
    expect(filsFromAed('0.01')).toBe(1)
    expect(filsFromAed('0')).toBe(0)
  })

  it('does not drift on values that break naive float maths', () => {
    // 5.55 * 100 === 554.9999999999999 in IEEE 754. This is the whole reason
    // the module exists, so it gets an explicit test.
    expect(filsFromAed('5.55')).toBe(555)
    expect(filsFromAed(5.55)).toBe(555)
    expect(filsFromAed('1.10')).toBe(110)
    expect(filsFromAed(0.1 + 0.2)).toBe(30)
  })

  it('handles negative amounts', () => {
    expect(filsFromAed('-12.34')).toBe(-1234)
  })

  it('rejects more precision than a fil can hold', () => {
    expect(() => filsFromAed('1.234')).toThrow(MoneyError)
  })

  it('rejects malformed input rather than guessing', () => {
    for (const bad of ['', 'abc', '1,50', '1.2.3', '--5', ' ', '1e3']) {
      expect(() => filsFromAed(bad)).toThrow(MoneyError)
    }
  })

  it('rejects non-finite numbers', () => {
    expect(() => filsFromAed(Number.NaN)).toThrow(MoneyError)
    expect(() => filsFromAed(Number.POSITIVE_INFINITY)).toThrow(MoneyError)
  })
})

describe('formatting', () => {
  it('round-trips through fils and back', () => {
    for (const value of ['0.00', '0.07', '9.90', '500.55', '123456.78']) {
      expect(aedFromFils(filsFromAed(value))).toBe(value)
    }
  })

  it('pads the fractional part', () => {
    expect(aedFromFils(fils(5))).toBe('0.05')
    expect(aedFromFils(fils(50))).toBe('0.50')
    expect(aedFromFils(fils(-5))).toBe('-0.05')
  })

  it('renders a human-facing string', () => {
    expect(formatAed(filsFromAed('500'))).toBe('500.00 AED')
  })
})

describe('arithmetic', () => {
  it('adds and subtracts', () => {
    expect(add(fils(100), fils(250))).toBe(350)
    expect(subtract(fils(350), fils(100))).toBe(250)
  })

  it('sums a list, empty included', () => {
    expect(sum([])).toBe(ZERO)
    expect(sum([fils(1), fils(2), fils(3)])).toBe(6)
  })

  it('refuses non-integer input', () => {
    expect(() => fils(1.5)).toThrow(MoneyError)
  })

  it('refuses amounts beyond the supported range', () => {
    expect(() => fils(Number.MAX_SAFE_INTEGER)).toThrow(MoneyError)
  })
})

describe('allocate', () => {
  it('splits evenly divisible amounts exactly', () => {
    expect(allocate(fils(10_000), [60, 40])).toEqual([6000, 4000])
    expect(allocate(fils(1000), [1, 1])).toEqual([500, 500])
  })

  it('distributes the remainder by largest fractional part, ties to the earlier index', () => {
    expect(allocate(fils(100), [1, 1, 1])).toEqual([34, 33, 33])
    expect(allocate(fils(10), [1, 1, 1])).toEqual([4, 3, 3])
  })

  it('handles a zero weight without giving it anything', () => {
    expect(allocate(fils(1000), [1, 0])).toEqual([1000, 0])
  })

  it('handles a zero total', () => {
    expect(allocate(ZERO, [70, 30])).toEqual([0, 0])
  })

  it('never loses or invents a fil, across a wide sweep of inputs', () => {
    const weightSets = [
      [1, 1],
      [1, 2],
      [60, 40],
      [1, 1, 1],
      [7, 11, 13],
      [1, 0, 1],
      [99, 1],
      [1, 1, 1, 1, 1, 1, 1],
    ]
    for (const weights of weightSets) {
      for (let total = 0; total <= 1000; total++) {
        const shares = allocate(fils(total), weights)
        expect(shares).toHaveLength(weights.length)
        expect(shares.every((s) => s >= 0)).toBe(true)
        expect(shares.reduce((a, b) => a + b, 0)).toBe(total)
      }
    }
  })

  it('is deterministic', () => {
    const a = allocate(fils(9_999), [7, 11, 13])
    const b = allocate(fils(9_999), [7, 11, 13])
    expect(a).toEqual(b)
  })

  it('rejects nonsense input', () => {
    expect(() => allocate(fils(100), [])).toThrow(MoneyError)
    expect(() => allocate(fils(100), [0, 0])).toThrow(MoneyError)
    expect(() => allocate(fils(100), [-1, 2])).toThrow(MoneyError)
    expect(() => allocate(fils(-100), [1, 1])).toThrow(MoneyError)
  })
})

describe('splitByPercent', () => {
  it('produces the split shown in the product demo', () => {
    // 500 AED, 60% to the seller: the numbers the landing page promises.
    const { seller, buyer } = splitByPercent(filsFromAed('500'), 60)
    expect(aedFromFils(seller)).toBe('300.00')
    expect(aedFromFils(buyer)).toBe('200.00')
  })

  it('gives everything to one side at the extremes', () => {
    expect(splitByPercent(fils(1000), 100)).toEqual({ seller: 1000, buyer: 0 })
    expect(splitByPercent(fils(1000), 0)).toEqual({ seller: 0, buyer: 1000 })
  })

  it('conserves the total at every whole percentage, for awkward amounts', () => {
    for (const total of [1, 7, 99, 333, 50_055, 1_000_001]) {
      for (let pct = 0; pct <= 100; pct++) {
        const { seller, buyer } = splitByPercent(fils(total), pct)
        expect(seller + buyer).toBe(total)
        expect(seller).toBeGreaterThanOrEqual(0)
        expect(buyer).toBeGreaterThanOrEqual(0)
      }
    }
  })

  it('rejects a percentage outside 0 to 100', () => {
    expect(() => splitByPercent(fils(100), 101)).toThrow(MoneyError)
    expect(() => splitByPercent(fils(100), -1)).toThrow(MoneyError)
    expect(() => splitByPercent(fils(100), Number.NaN)).toThrow(MoneyError)
  })
})
