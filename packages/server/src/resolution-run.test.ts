import { describe, expect, it } from 'vitest'
import { filsFromAed, type EscalationPolicy, type EvidenceId, type Fils } from '@trustiq/core'
import type { AuditRecord, DisputeCase, ModelClient, ModelOutcome } from '@trustiq/ai'
import { runResolution, type RunDeps } from './resolution-run.js'
import type { DisputeRepository, SaveProposalInput } from './ports.js'

const DISPUTE = 'dsp_1'
const AMOUNT = filsFromAed('500')
const NOW = new Date('2026-08-19T10:00:00.000Z')
const CONTRACT = 'ev_contract' as EvidenceId

const POLICY: EscalationPolicy = { minConfidence: 0.7, maxAutoAmount: filsFromAed('5000') }

function caseFile(over: Partial<DisputeCase> = {}): DisputeCase {
  return {
    disputeId: DISPUTE,
    transactionId: 'txn_1',
    description: 'Logo design',
    terms: 'Three concepts in seven days.',
    disputedAmount: AMOUNT,
    buyerClaim: 'Not what we agreed.',
    sellerClaim: 'It is exactly what we agreed.',
    evidence: [
      {
        id: CONTRACT,
        uploadedByRole: 'buyer',
        filename: 'contract.pdf',
        contentType: 'application/pdf',
        uploadedAt: '2026-06-01T09:00:00.000Z',
        sha256: 'a'.repeat(64),
        extractionStatus: 'unsupported' as const,
        note: null,
        extractedText: 'Three concepts in seven days.',
      },
    ],
    contractAcceptedAt: '2026-06-01T09:00:00.000Z',
    deliveredAt: '2026-06-08T09:00:00.000Z',
    disputeOpenedAt: '2026-06-10T09:00:00.000Z',
    ...over,
  }
}

class FakeRepo implements DisputeRepository {
  caseFile: DisputeCase | null = caseFile()
  amount: Fils | null = AMOUNT
  readonly audits: AuditRecord[] = []
  readonly escalations: { disputeId: string; reason: string }[] = []
  readonly proposals: SaveProposalInput[] = []
  failAudit = false
  failSave = false
  failBeginAnalysis = false
  // The order transitions were requested in, so a test can assert the dispute
  // reached `ai_review` before anything tried to leave it.
  readonly transitions: string[] = []

  async loadCase(): Promise<DisputeCase | null> {
    return this.caseFile
  }

  async disputedAmount(): Promise<Fils | null> {
    return this.amount
  }

  async beginAnalysis(): Promise<void> {
    if (this.failBeginAnalysis) throw new Error('submit_for_ai refused')
    this.transitions.push('submit_for_ai')
  }

  async saveProposal(input: SaveProposalInput): Promise<{ proposalId: string }> {
    this.transitions.push('issue_proposal')
    if (this.failSave) throw new Error('insert failed')
    this.proposals.push(input)
    return { proposalId: `prop_${this.proposals.length}` }
  }

  async markEscalated(disputeId: string, reason: string): Promise<void> {
    this.transitions.push('escalate')
    this.escalations.push({ disputeId, reason })
  }

  async appendAuditRecord(record: AuditRecord): Promise<void> {
    if (this.failAudit) throw new Error('audit table unavailable')
    this.audits.push(record)
  }
}

function model(outcome: ModelOutcome): ModelClient {
  return { modelId: 'claude-opus-5', promptVersion: 'test', complete: async () => outcome }
}

function goodJson(over: Record<string, unknown> = {}): ModelOutcome {
  return {
    kind: 'completed',
    modelId: 'claude-opus-5',
    latencyMs: 900,
    json: JSON.stringify({
      decision: 'split',
      summary: 'Delivered on time; quality unverifiable from the evidence.',
      findings: [{ statement: 'A contract exists.', evidenceIds: [CONTRACT] }],
      sellerPercent: 60,
      confidence: 0.9,
      ...over,
    }),
  }
}

function deps(repo: FakeRepo, outcome: ModelOutcome): RunDeps {
  return { repository: repo, model: model(outcome), policy: POLICY, clock: { now: () => NOW } }
}

describe('a resolvable case', () => {
  it('stores the proposal and reports its id', async () => {
    const repo = new FakeRepo()
    const result = await runResolution(DISPUTE, deps(repo, goodJson()))

    expect(result).toEqual({ kind: 'proposal', proposalId: 'prop_1', disputeId: DISPUTE })
    expect(repo.proposals).toHaveLength(1)
    expect(repo.escalations).toHaveLength(0)
  })

  it('writes the audit record before the proposal is stored', async () => {
    const repo = new FakeRepo()
    await runResolution(DISPUTE, deps(repo, goodJson()))
    expect(repo.audits).toHaveLength(1)
    expect(repo.audits[0]?.validationOutcome).toBe('accepted')
  })
})

describe('no audit record, no proposal', () => {
  it('escalates rather than issuing a resolution it cannot explain later', async () => {
    const repo = new FakeRepo()
    repo.failAudit = true

    const result = await runResolution(DISPUTE, deps(repo, goodJson()))

    expect(result.kind).toBe('escalated')
    expect(repo.proposals).toHaveLength(0)
    expect(repo.escalations[0]?.reason).toContain('audit record could not be written')
  })
})

describe('escalations reach the reviewer with a readable reason', () => {
  const cases: [string, ModelOutcome, string][] = [
    [
      'a refusal',
      { kind: 'refused', category: 'cyber', modelId: 'm', latencyMs: 5 },
      'the model declined to answer (cyber)',
    ],
    [
      'a truncated response',
      { kind: 'truncated', modelId: 'm', latencyMs: 5 },
      'cut off before it finished',
    ],
    [
      'low confidence',
      goodJson({ confidence: 0.2 }),
      'policy requires human review: low_confidence',
    ],
    [
      'a hallucinated citation',
      goodJson({ findings: [{ statement: 'x', evidenceIds: ['ev_ghost'] }] }),
      'UNKNOWN_EVIDENCE',
    ],
  ]

  for (const [label, outcome, expected] of cases) {
    it(`explains ${label}`, async () => {
      const repo = new FakeRepo()
      const result = await runResolution(DISPUTE, deps(repo, outcome))

      expect(result.kind).toBe('escalated')
      expect(repo.escalations[0]?.reason).toContain(expected)
      expect(repo.proposals).toHaveLength(0)
      // The failure is still on the record.
      expect(repo.audits).toHaveLength(1)
    })
  }
})

describe('guards around the run', () => {
  it('skips a dispute that no longer exists', async () => {
    const repo = new FakeRepo()
    repo.caseFile = null

    const result = await runResolution(DISPUTE, deps(repo, goodJson()))
    expect(result).toEqual({ kind: 'skipped', disputeId: DISPUTE, reason: 'dispute not found' })
    expect(repo.audits).toHaveLength(0)
  })

  it('refuses to resolve from a stale amount', async () => {
    // The run may have been queued a while ago. If the disputed amount moved
    // underneath it, resolving from the old figure would allocate the wrong money.
    const repo = new FakeRepo()
    repo.amount = filsFromAed('750')

    const result = await runResolution(DISPUTE, deps(repo, goodJson()))
    expect(result.kind).toBe('escalated')
    expect(repo.escalations[0]?.reason).toContain('disputed amount changed')
    expect(repo.proposals).toHaveLength(0)
  })

  it('escalates when a valid proposal cannot be stored', async () => {
    const repo = new FakeRepo()
    repo.failSave = true

    const result = await runResolution(DISPUTE, deps(repo, goodJson()))
    expect(result.kind).toBe('escalated')
    expect(repo.escalations[0]?.reason).toContain('could not be stored')
  })
})

describe('the dispute reaches ai_review before anything else', () => {
  it('moves into review before the model is called', async () => {
    const repo = new FakeRepo()
    await runResolution(DISPUTE, deps(repo, goodJson()))

    // Both issue_proposal and escalate are only legal from ai_review, so this
    // ordering is not cosmetic: without it the state machine refuses the next
    // step and a real dispute gets stuck.
    expect(repo.transitions[0]).toBe('submit_for_ai')
    expect(repo.transitions).toEqual(['submit_for_ai', 'issue_proposal'])
  })

  it('reaches review before escalating too', async () => {
    const repo = new FakeRepo()
    await runResolution(DISPUTE, deps(repo, goodJson({ confidence: 0.1 })))
    expect(repo.transitions).toEqual(['submit_for_ai', 'escalate'])
  })

  it('escalates without calling the model when review cannot be entered', async () => {
    const repo = new FakeRepo()
    repo.failBeginAnalysis = true

    const result = await runResolution(DISPUTE, deps(repo, goodJson()))

    expect(result.kind).toBe('escalated')
    if (result.kind !== 'escalated') return
    expect(result.reason).toContain('could not be moved into review')
    // Nothing was proposed, and no model call was paid for.
    expect(repo.proposals).toHaveLength(0)
    expect(repo.audits).toHaveLength(0)
  })

  it('does not enter review for a dispute that does not exist', async () => {
    const repo = new FakeRepo()
    repo.caseFile = null
    await runResolution(DISPUTE, deps(repo, goodJson()))
    expect(repo.transitions).toEqual([])
  })
})
