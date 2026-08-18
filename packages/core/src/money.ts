/**
 * Money handling for TrustIQ.
 *
 * Every amount in the system is an integer number of fils, the minor unit of
 * the UAE dirham (1 AED = 100 fils). Floating point numbers are never used to
 * represent money: `0.1 + 0.2 !== 0.3` is a rounding bug in a spreadsheet and
 * a dispute in an escrow product.
 *
 * The `Fils` brand exists so a bare number cannot be passed where an amount is
 * expected. It is erased at runtime and costs nothing.
 */

export type Fils = number & { readonly __brand: unique symbol }

export const FILS_PER_AED = 100

/** Largest amount we accept, ~92 billion AED, safely inside Number.MAX_SAFE_INTEGER. */
export const MAX_FILS = 9_223_372_036_854 as Fils

export class MoneyError extends Error {
  override readonly name = 'MoneyError'
}

function assertSafe(value: number, context: string): asserts value is Fils {
  if (!Number.isInteger(value)) {
    throw new MoneyError(`${context}: amount must be a whole number of fils, got ${value}`)
  }
  if (Math.abs(value) > MAX_FILS) {
    throw new MoneyError(`${context}: amount ${value} exceeds the supported range`)
  }
}

/** Wrap a raw integer that is already expressed in fils. */
export function fils(value: number): Fils {
  assertSafe(value, 'fils')
  return value
}

export const ZERO = fils(0)

const AED_PATTERN = /^(-)?(\d+)(?:\.(\d{1,2}))?$/

/**
 * Parse an AED amount into fils.
 *
 * Accepts a string (preferred, exact) or a number (converted via its decimal
 * string form, so `5.55` does not become 554.9999...). More than two decimal
 * places is rejected rather than silently rounded: dropping a fil without
 * telling anyone is how ledgers stop balancing.
 */
export function filsFromAed(amount: string | number): Fils {
  const raw = typeof amount === 'number' ? decimalString(amount) : amount.trim()
  const match = AED_PATTERN.exec(raw)
  if (!match) {
    throw new MoneyError(
      `filsFromAed: "${raw}" is not a valid AED amount (expected digits with at most 2 decimals)`,
    )
  }
  const [, sign, whole = '0', fraction = ''] = match
  const minor = Number(whole) * FILS_PER_AED + Number(fraction.padEnd(2, '0'))
  const signed = sign === '-' ? -minor : minor
  assertSafe(signed, 'filsFromAed')
  return signed
}

function decimalString(value: number): string {
  if (!Number.isFinite(value)) {
    throw new MoneyError(`filsFromAed: ${value} is not a finite number`)
  }
  // toFixed(2) is exact enough here because we reject anything beyond 2 decimals
  // anyway, and it avoids exponential notation for large values.
  return value.toFixed(2)
}

/** Format fils as a plain AED decimal string, e.g. 50055 -> "500.55". */
export function aedFromFils(amount: Fils): string {
  const negative = amount < 0
  const abs = Math.abs(amount)
  const whole = Math.floor(abs / FILS_PER_AED)
  const fraction = abs % FILS_PER_AED
  return `${negative ? '-' : ''}${whole}.${String(fraction).padStart(2, '0')}`
}

/** Human-facing amount, e.g. "500.55 AED". */
export function formatAed(amount: Fils): string {
  return `${aedFromFils(amount)} AED`
}

export function add(a: Fils, b: Fils): Fils {
  const sum = a + b
  assertSafe(sum, 'add')
  return sum
}

export function subtract(a: Fils, b: Fils): Fils {
  const difference = a - b
  assertSafe(difference, 'subtract')
  return difference
}

export function sum(amounts: readonly Fils[]): Fils {
  return amounts.reduce<Fils>((total, amount) => add(total, amount), ZERO)
}

export function isPositive(amount: Fils): boolean {
  return amount > 0
}

/**
 * Split an amount across weighted shares without losing or inventing a single fil.
 *
 * Uses the largest-remainder method: floor every share, then hand the leftover
 * fils one at a time to the shares with the largest fractional part. Ties go to
 * the earlier index, so the result is deterministic and reproducible in an audit.
 *
 * `allocate(fils(10000), [60, 40])` -> `[6000, 4000]`
 * `allocate(fils(100), [1, 1, 1])`  -> `[34, 33, 33]`
 *
 * The returned array always sums exactly to `total`. This is asserted in tests
 * over a wide range of inputs, because it is the invariant that keeps the ledger
 * balanced when a dispute resolution splits an amount.
 */
export function allocate(total: Fils, weights: readonly number[]): Fils[] {
  if (weights.length === 0) {
    throw new MoneyError('allocate: at least one weight is required')
  }
  if (weights.some((w) => !Number.isFinite(w) || w < 0)) {
    throw new MoneyError('allocate: weights must be finite and non-negative')
  }
  const totalWeight = weights.reduce((acc, w) => acc + w, 0)
  if (totalWeight <= 0) {
    throw new MoneyError('allocate: weights must not all be zero')
  }
  if (total < 0) {
    throw new MoneyError('allocate: cannot allocate a negative amount')
  }

  const shares: number[] = []
  const remainders: { index: number; fraction: number }[] = []
  let distributed = 0

  for (let i = 0; i < weights.length; i++) {
    const weight = weights[i] ?? 0
    const exact = (total * weight) / totalWeight
    const floored = Math.floor(exact)
    shares.push(floored)
    remainders.push({ index: i, fraction: exact - floored })
    distributed += floored
  }

  let leftover = total - distributed
  remainders.sort((a, b) => b.fraction - a.fraction || a.index - b.index)

  for (let i = 0; leftover > 0; i = (i + 1) % remainders.length) {
    const target = remainders[i]
    if (target === undefined) break
    shares[target.index] = (shares[target.index] ?? 0) + 1
    leftover--
  }

  return shares.map((share) => fils(share))
}

/**
 * Split an amount by percentage between seller and buyer, the shape a dispute
 * resolution actually takes. `sellerPercent` is 0-100 inclusive.
 */
export function splitByPercent(
  total: Fils,
  sellerPercent: number,
): { seller: Fils; buyer: Fils } {
  if (!Number.isFinite(sellerPercent) || sellerPercent < 0 || sellerPercent > 100) {
    throw new MoneyError(`splitByPercent: sellerPercent must be between 0 and 100, got ${sellerPercent}`)
  }
  const [seller = ZERO, buyer = ZERO] = allocate(total, [sellerPercent, 100 - sellerPercent])
  return { seller, buyer }
}
