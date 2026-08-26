/**
 * A plain Result type.
 *
 * The domain layer never throws for outcomes that are expected, such as a party
 * attempting a transition they are not allowed to make. Those are values the
 * caller must handle. Exceptions are reserved for programmer error (see
 * MoneyError), which should never reach a user.
 */

export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E }

export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value }
}

export function err<E>(error: E): Result<never, E> {
  return { ok: false, error }
}

export function isOk<T, E>(result: Result<T, E>): result is { readonly ok: true; readonly value: T } {
  return result.ok
}

export function isErr<T, E>(result: Result<T, E>): result is { readonly ok: false; readonly error: E } {
  return !result.ok
}

/** Unwrap a Result, throwing if it failed. For tests and trusted call sites only. */
export function unwrap<T, E>(result: Result<T, E>): T {
  if (result.ok) return result.value
  throw new Error(`unwrap called on a failed Result: ${JSON.stringify(result.error)}`)
}
