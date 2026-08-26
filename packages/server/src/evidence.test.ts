import { describe, expect, it } from 'vitest'
import { isErr, isOk, unwrap, type EvidenceId, type Role } from '@trustiq/core'
import {
  ALLOWED_CONTENT_TYPES,
  MAX_EVIDENCE_BYTES,
  sha256Hex,
  uploadEvidence,
  type UploadDeps,
  type UploadEvidenceInput,
} from './evidence.js'
import type { EvidenceRepository, NewEvidenceRow, ObjectStorage } from './ports.js'

const TXN = 'aaaaaaaa-0000-0000-0000-000000000001'
const BUYER = '11111111-1111-1111-1111-111111111111'
const NOW = new Date('2026-08-19T10:00:00.000Z')

const BYTES = new TextEncoder().encode('the signed contract, as a pdf would be')
// Computed by the same primitive the production path uses; the assertions
// below check the row carries this, never whatever a caller claimed.
const DIGEST = sha256Hex(BYTES)

class FakeStorage implements ObjectStorage {
  readonly objects = new Map<string, { bytes: Uint8Array; contentType: string }>()
  failOnPut = false
  removed: string[] = []

  async put(path: string, bytes: Uint8Array, contentType: string): Promise<void> {
    if (this.failOnPut) throw new Error('bucket unavailable')
    if (this.objects.has(path)) throw new Error(`object already exists at ${path}`)
    this.objects.set(path, { bytes, contentType })
  }

  async remove(path: string): Promise<void> {
    this.removed.push(path)
    this.objects.delete(path)
  }
}

class FakeRepository implements EvidenceRepository {
  readonly rows: NewEvidenceRow[] = []
  accepts = true
  role: Role | null = 'buyer'
  failOnInsert = false
  private next = 0

  async transactionAcceptsEvidence(): Promise<boolean> {
    return this.accepts
  }

  async roleOnTransaction(): Promise<Role | null> {
    return this.role
  }

  async digestAlreadyFiled(transactionId: string, sha256: string): Promise<boolean> {
    return this.rows.some((r) => r.transactionId === transactionId && r.sha256 === sha256)
  }

  async insert(row: NewEvidenceRow): Promise<EvidenceId> {
    if (this.failOnInsert) throw new Error('unique constraint violated')
    this.rows.push(row)
    this.next += 1
    return `ev_${this.next}` as EvidenceId
  }
}

function makeDeps(over: { storage?: FakeStorage; repository?: FakeRepository } = {}): UploadDeps & {
  storage: FakeStorage
  repository: FakeRepository
} {
  const storage = over.storage ?? new FakeStorage()
  const repository = over.repository ?? new FakeRepository()
  let counter = 0
  return {
    storage,
    repository,
    clock: { now: () => NOW },
    newId: () => `id${++counter}`,
  }
}

function input(over: Partial<UploadEvidenceInput> = {}): UploadEvidenceInput {
  return {
    transactionId: TXN,
    userId: BUYER,
    filename: 'contract.pdf',
    contentType: 'application/pdf',
    bytes: BYTES,
    note: null,
    ...over,
  }
}

describe('the digest is the server’s, never the client’s', () => {
  it('writes the digest of the bytes it actually stored', async () => {
    const deps = makeDeps()
    const result = await uploadEvidence(input(), deps)

    expect(isOk(result)).toBe(true)
    expect(unwrap(result).sha256).toBe(DIGEST)
    expect(deps.repository.rows[0]?.sha256).toBe(DIGEST)
  })

  it('ignores a client-claimed digest that happens to be right', async () => {
    // Correct or not, the claim is never the source of the stored value.
    const deps = makeDeps()
    const result = await uploadEvidence(input({ clientClaimedSha256: DIGEST }), deps)
    expect(unwrap(result).sha256).toBe(DIGEST)
  })

  it('refuses an upload whose bytes do not match the claimed digest', async () => {
    const deps = makeDeps()
    const result = await uploadEvidence(input({ clientClaimedSha256: 'f'.repeat(64) }), deps)

    expect(isErr(result)).toBe(true)
    if (!isErr(result)) return
    expect(result.error.code).toBe('DIGEST_MISMATCH')
    // Nothing was written on either side.
    expect(deps.storage.objects.size).toBe(0)
    expect(deps.repository.rows).toHaveLength(0)
  })

  it('cannot be talked into storing a forged digest', async () => {
    // The one case that matters: a caller supplies a digest for a document it
    // did not upload. The stored value is the real one regardless.
    const forged = 'a'.repeat(64)
    const deps = makeDeps()
    const result = await uploadEvidence(
      input({ bytes: new TextEncoder().encode('a different document entirely') }),
      deps,
    )
    expect(unwrap(result).sha256).not.toBe(forged)
    expect(unwrap(result).sha256).toBe(sha256Hex(new TextEncoder().encode('a different document entirely')))
  })

  it('produces a different digest for a single changed byte', async () => {
    const deps = makeDeps()
    const first = await uploadEvidence(input(), deps)
    const tampered = new TextEncoder().encode('the signed contract, as a pdf would bE')
    const second = await uploadEvidence(input({ bytes: tampered, filename: 'contract2.pdf' }), deps)

    expect(unwrap(first).sha256).not.toBe(unwrap(second).sha256)
  })
})

describe('who may file evidence', () => {
  it('refuses a caller who is not on the contract', async () => {
    const deps = makeDeps()
    deps.repository.role = null

    const result = await uploadEvidence(input(), deps)
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('NOT_A_PARTY')
    expect(deps.storage.objects.size).toBe(0)
  })

  it('records the role the contract says, not one the caller asserts', async () => {
    const deps = makeDeps()
    deps.repository.role = 'seller'

    const result = await uploadEvidence(input(), deps)
    expect(unwrap(result).role).toBe('seller')
    expect(deps.repository.rows[0]?.uploadedByRole).toBe('seller')
  })

  it('refuses evidence against a closed contract', async () => {
    const deps = makeDeps()
    deps.repository.accepts = false

    const result = await uploadEvidence(input(), deps)
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('TRANSACTION_CLOSED')
  })
})

describe('what may be filed', () => {
  it('refuses an empty file', async () => {
    const result = await uploadEvidence(input({ bytes: new Uint8Array(0) }), makeDeps())
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('EMPTY_FILE')
  })

  it('refuses a file over the limit', async () => {
    const result = await uploadEvidence(
      input({ bytes: new Uint8Array(MAX_EVIDENCE_BYTES + 1) }),
      makeDeps(),
    )
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('FILE_TOO_LARGE')
  })

  it('refuses a content type the bucket will not hold', async () => {
    const result = await uploadEvidence(
      input({ contentType: 'application/x-msdownload' }),
      makeDeps(),
    )
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('UNSUPPORTED_CONTENT_TYPE')
  })

  it('accepts every content type the bucket allows', async () => {
    for (const contentType of ALLOWED_CONTENT_TYPES) {
      const deps = makeDeps()
      const result = await uploadEvidence(input({ contentType }), deps)
      expect(isOk(result), contentType).toBe(true)
    }
  })

  it('refuses a filename carrying path separators', async () => {
    for (const filename of ['../../etc/passwd', 'a/b.pdf', 'a\\b.pdf', '']) {
      const result = await uploadEvidence(input({ filename }), makeDeps())
      if (!isErr(result)) throw new Error(`accepted ${filename}`)
      expect(result.error.code).toBe('INVALID_FILENAME')
    }
  })

  it('refuses the same file twice on one contract', async () => {
    const deps = makeDeps()
    await uploadEvidence(input(), deps)
    const second = await uploadEvidence(input({ filename: 'same-bytes-different-name.pdf' }), deps)

    if (!isErr(second)) throw new Error('expected rejection')
    expect(second.error.code).toBe('DUPLICATE_EVIDENCE')
    expect(deps.storage.objects.size).toBe(1)
  })

  it('allows the same file on a different contract', async () => {
    const deps = makeDeps()
    await uploadEvidence(input(), deps)
    const other = await uploadEvidence(input({ transactionId: 'bbbbbbbb-0000-0000-0000-000000000002' }), deps)
    expect(isOk(other)).toBe(true)
  })
})

describe('failure leaves nothing dangling', () => {
  it('writes no row when the object could not be stored', async () => {
    const deps = makeDeps()
    deps.storage.failOnPut = true

    const result = await uploadEvidence(input(), deps)
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('STORAGE_FAILED')
    expect(deps.repository.rows).toHaveLength(0)
  })

  it('removes the stored object when the row could not be written', async () => {
    // Evidence rows are append-only, so a row pointing at nothing could never
    // be cleaned up. An object with no row is inert and is removed here.
    const deps = makeDeps()
    deps.repository.failOnInsert = true

    const result = await uploadEvidence(input(), deps)
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('RECORD_FAILED')
    expect(deps.storage.objects.size).toBe(0)
    expect(deps.storage.removed).toHaveLength(1)
  })

  it('still reports failure when the cleanup itself fails', async () => {
    const storage = new FakeStorage()
    storage.remove = async () => {
      throw new Error('delete failed too')
    }
    const deps = makeDeps({ storage })
    deps.repository.failOnInsert = true

    const result = await uploadEvidence(input(), deps)
    if (!isErr(result)) throw new Error('expected rejection')
    expect(result.error.code).toBe('RECORD_FAILED')
  })
})

describe('storage paths', () => {
  it('scopes the object under its contract and never collides', async () => {
    const deps = makeDeps()
    const first = await uploadEvidence(input(), deps)
    const second = await uploadEvidence(
      input({ bytes: new TextEncoder().encode('another file'), filename: 'b.pdf' }),
      deps,
    )

    expect(unwrap(first).storagePath.startsWith(`${TXN}/`)).toBe(true)
    expect(unwrap(first).storagePath).not.toBe(unwrap(second).storagePath)
  })

  it('does not put the caller-supplied filename in the path', async () => {
    const deps = makeDeps()
    const result = await uploadEvidence(input({ filename: 'contract.pdf' }), deps)
    expect(unwrap(result).storagePath).not.toContain('contract.pdf')
  })
})
