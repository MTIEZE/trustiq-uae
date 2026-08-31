import { useState } from 'react'
import { Nav, Footer, BetaForm } from './components/Shell.jsx'
import './App.css'

// A real run of the resolution pipeline, copied out of the production audit
// log. Nothing here is written by hand: the findings, the summary, the split
// and the numbers below are what claude-opus-5 returned on 30 August 2026, and
// the audit row is the row that recorded it.
//
// The dispute it ran on is a test case rather than a customer's, which is said
// on the page. What is not a test is the run.
const RECORDED_RUN = {
  contract: {
    reference: 'Logo design for a startup',
    terms: 'Deliver 3 distinct logo concepts within 7 days. Two rounds of revision included. Final files supplied as SVG and PNG.',
    amount: '500 AED',
  },
  buyerClaim:
    'Only two usable concepts were delivered. The third is a colour variation of the second, not a distinct concept as the brief required.',
  sellerClaim:
    'Three concepts were delivered inside the agreed window. The client changed direction after seeing them.',
  findings: [
    'The agreed brief required three distinct logo concepts within seven days, delivered as SVG and PNG.',
    "The seller's own delivery note records that what was sent was two concepts plus a colour variation, not three distinct concepts.",
    'Delivery occurred on 8 August 2026, within seven days of the brief signed 1 August 2026, so the deadline was met.',
  ],
  decision: 'Split',
  split: { seller: '325.00 AED', buyer: '175.00 AED', sellerPct: 65 },
  summary:
    'Both sides agree three concepts were promised within seven days, with final files in SVG and PNG. The seller\u2019s own delivery note describes what was sent as \u201Ctwo concepts plus a colour variation\u201D, which matches the buyer\u2019s account rather than the seller\u2019s claim of three distinct concepts. Delivery on 8 August was within seven days of the brief signed 1 August, so timing was met, and the seller clearly did substantial work; but one of the three required concepts was not distinct. Nothing submitted shows whether the SVG and PNG files were supplied, and the seller\u2019s claim that the client changed direction is not supported by any evidence, so neither point is weighed. On that basis the seller is credited for roughly the two-thirds of the concept work actually delivered, with a modest deduction reflecting the shortfall against the agreed brief.',
  audit: {
    model: 'claude-opus-5',
    promptVersion: '2026-08-26.1',
    confidence: '0.720',
    latency: '12,290 ms',
    outcome: 'accepted',
  },
}

// The two the system refused to pass on. These matter more than the one that
// worked: they are the difference between an agent that answers and an agent
// that knows when not to.
const REFUSED_RUNS = [
  {
    outcome: 'ESCALATED_BY_POLICY',
    confidence: '0.150',
    latency: '5,902 ms',
    why: 'The model was not confident enough. Below the policy threshold a case goes to a person instead of to the parties.',
  },
  {
    outcome: 'UNGROUNDED_FINDING',
    confidence: '0.220',
    latency: '9,614 ms',
    why: 'One finding cited a document that was never filed. Validation rejected the whole proposal rather than the sentence.',
  },
]

function Hero() {
  return (
    <section className="hero">
      <div className="container">
        <span className="label">AI-Powered Trust Infrastructure</span>
        <h1>Secure transactions between strangers in the UAE</h1>
        <p className="hero-sub">
          TrustIQ turns a handshake between strangers into a tracked contract: agreed terms,
          timestamped evidence, and a delivery both sides can follow. When something goes wrong,
          an AI agent reads the evidence and proposes a fair resolution in under 60 seconds.
        </p>
        <a href="#how-it-works" className="hero-cta">See How It Works</a>
        <div className="hero-pills">
          <span className="pill"><span className="pill-dot"></span>Digital Contracts</span>
          <span className="pill"><span className="pill-dot"></span>Timestamped Evidence</span>
          <span className="pill"><span className="pill-dot"></span>AI Dispute Resolution</span>
          <span className="pill upcoming"><span className="pill-dot"></span>Escrow · v2</span>
        </div>
        <p className="hero-note">
          Escrow, where payment is held until both parties confirm, ships in v2 with a licensed
          UAE payment partner. Everything else is what TrustIQ does today.
        </p>
      </div>
    </section>
  )
}

function Problem() {
  return (
    <section className="problem">
      <div className="container">
        <span className="label">The Problem</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>The trust gap in peer-to-peer transactions</h2>
        <div className="problem-grid">
          <div className="problem-card">
            <div className="icon">🤝</div>
            <h3>Freelancer vs. Client</h3>
            <p>Who pays first? The freelancer risks unpaid work. The client risks paying for subpar delivery. Neither has recourse.</p>
          </div>
          <div className="problem-card">
            <div className="icon">🏪</div>
            <h3>Merchant vs. Buyer</h3>
            <p>Small merchants and buyers transacting without platform guarantees face delivery and payment disputes with no resolution path.</p>
          </div>
          <div className="problem-card">
            <div className="icon">🏢</div>
            <h3>SME vs. SME</h3>
            <p>B2B deals between small businesses lack the legal infrastructure of enterprise contracts, leaving both parties exposed.</p>
          </div>
        </div>
      </div>
    </section>
  )
}

function HowItWorks() {
  const [activeStep, setActiveStep] = useState(0)

  const steps = [
    {
      num: '01',
      title: 'Both parties sign up',
      subtitle: 'REGISTRATION',
      icon: '👤',
      description: 'The buyer and the seller each create a TrustIQ account with their name, email, and phone number. Their profiles are stored securely in Supabase.',
      visual: (
        <div className="step-visual">
          <div className="mock-card">
            <div className="mock-card-header">
              <span className="label">Create Account</span>
            </div>
            <div className="mock-field"><span className="mock-label">FULL NAME</span><span className="mock-value">Ahmed Al-Rashid</span></div>
            <div className="mock-field"><span className="mock-label">EMAIL</span><span className="mock-value">ahmed@startup.ae</span></div>
            <div className="mock-field"><span className="mock-label">PHONE</span><span className="mock-value">+971 55 XXX XXXX</span></div>
            <div className="mock-btn">Create Account</div>
          </div>
          <div className="mock-card">
            <div className="mock-card-header">
              <span className="label">Create Account</span>
            </div>
            <div className="mock-field"><span className="mock-label">FULL NAME</span><span className="mock-value">Sara Design Studio</span></div>
            <div className="mock-field"><span className="mock-label">EMAIL</span><span className="mock-value">sara@design.ae</span></div>
            <div className="mock-field"><span className="mock-label">PHONE</span><span className="mock-value">+971 50 XXX XXXX</span></div>
            <div className="mock-btn">Create Account</div>
          </div>
        </div>
      )
    },
    {
      num: '02',
      title: 'They create a transaction',
      subtitle: 'CONTRACT',
      icon: '📝',
      description: 'The buyer initiates a transaction by describing the service, setting the amount, and selecting the seller. Both parties agree to the terms. This acts as a digital contract.',
      visual: (
        <div className="step-visual">
          <div className="mock-card wide">
            <div className="mock-card-header">
              <span className="label">New Transaction</span>
              <span className="status-pill pending"><span className="pill-dot"></span>Draft</span>
            </div>
            <div className="mock-field"><span className="mock-label">DESCRIPTION</span><span className="mock-value">Logo design for a startup</span></div>
            <div className="mock-row">
              <div className="mock-field"><span className="mock-label">AMOUNT</span><span className="mock-value accent">500 AED</span></div>
              <div className="mock-field"><span className="mock-label">BUYER</span><span className="mock-value">Ahmed Al-Rashid</span></div>
              <div className="mock-field"><span className="mock-label">SELLER</span><span className="mock-value">Sara Design Studio</span></div>
            </div>
            <div className="mock-terms">
              <span className="mock-label">TERMS</span>
              <p>Deliver 3 logo concepts within 7 days. Client gets 2 rounds of revision. Final files in SVG + PNG.</p>
            </div>
            <div className="mock-signatures">
              <div className="mock-sig signed">✓ Ahmed signed</div>
              <div className="mock-sig signed">✓ Sara signed</div>
            </div>
            <div className="mock-btn">Confirm & Lock Payment</div>
          </div>
        </div>
      )
    },
    {
      num: '03',
      title: 'Payment, and where it will sit in v2',
      subtitle: 'ESCROW \u00b7 V2',
      icon: '🔒',
      phase: 'v2',
      description: 'Once both parties sign, the buyer\'s payment (500 AED) is locked in TrustIQ escrow. The seller can start working, knowing the money is secured. The buyer knows the money won\'t be released until the job is done. Holding funds in the UAE requires a licensed partner, so this step ships in v2. In v1 the parties pay each other directly, and every other step below works exactly as shown.',
      visual: (
        <div className="step-visual">
          <div className="mock-card wide">
            <div className="mock-card-header">
              <span className="label">Transaction #TIQ-2024-0847</span>
              <span className="status-pill locked"><span className="pill-dot"></span>Escrow Locked</span>
            </div>
            <div className="escrow-visual">
              <div className="escrow-party">
                <span className="mock-label">BUYER</span>
                <span className="escrow-name">Ahmed</span>
                <span className="escrow-action sent">-500 AED</span>
              </div>
              <div className="escrow-vault">
                <div className="vault-icon">🔒</div>
                <span className="vault-amount">500 AED</span>
                <span className="mock-label">SECURED</span>
              </div>
              <div className="escrow-party">
                <span className="mock-label">SELLER</span>
                <span className="escrow-name">Sara</span>
                <span className="escrow-action waiting">Pending</span>
              </div>
            </div>
            <div className="escrow-note">Payment held securely until both parties confirm completion</div>
          </div>
        </div>
      )
    },
    {
      num: '04',
      title: 'Seller delivers, buyer confirms',
      subtitle: 'DELIVERY',
      icon: '✅',
      description: 'The seller completes the work and marks the delivery as done. The buyer reviews and can either confirm satisfaction, which closes the contract and clears payment, or open a dispute if something is wrong.',
      visual: (
        <div className="step-visual">
          <div className="mock-card wide">
            <div className="mock-card-header">
              <span className="label">Transaction #TIQ-2024-0847</span>
              <span className="status-pill locked"><span className="pill-dot"></span>Delivery Review</span>
            </div>
            <div className="delivery-timeline">
              <div className="timeline-item done">
                <div className="timeline-dot done"></div>
                <div className="timeline-content">
                  <span className="mock-label">JUNE 1</span>
                  <span>Contract signed, escrow locked</span>
                </div>
              </div>
              <div className="timeline-item done">
                <div className="timeline-dot done"></div>
                <div className="timeline-content">
                  <span className="mock-label">JUNE 8</span>
                  <span>Sara delivered 3 logo concepts</span>
                </div>
              </div>
              <div className="timeline-item current">
                <div className="timeline-dot current"></div>
                <div className="timeline-content">
                  <span className="mock-label">AWAITING BUYER REVIEW</span>
                  <span>Ahmed must confirm or dispute</span>
                </div>
              </div>
            </div>
            <div className="delivery-actions">
              <div className="mock-btn success">✓ Confirm & Release Payment</div>
              <div className="mock-btn danger">✕ Open Dispute</div>
            </div>
          </div>
        </div>
      )
    },
    {
      num: '05',
      title: 'Dispute? AI proposes a resolution in 60 seconds',
      subtitle: 'AI RESOLUTION',
      icon: '🧠',
      description: 'If the buyer is not satisfied and opens a dispute, both parties submit their claims and evidence. TrustIQ\'s AI agent analyzes everything and proposes a structured resolution. The AI does not rule: the dispute closes only when both parties accept the proposal, and a single refusal sends the case to a human reviewer.',
      visual: (
        <div className="step-visual">
          <div className="mock-card wide ai-glow">
            <div className="mock-card-header">
              <span className="ai-badge"><span className="ai-badge-dot"></span>AI Dispute Resolution</span>
              <span className="status-pill disputed"><span className="pill-dot"></span>Disputed</span>
            </div>
            <div className="dispute-claims">
              <div className="claim-box buyer">
                <span className="mock-label">BUYER CLAIM</span>
                <p>"The designer delivered low quality work that does not match what was agreed."</p>
              </div>
              <div className="claim-vs">VS</div>
              <div className="claim-box seller">
                <span className="mock-label">SELLER CLAIM</span>
                <p>"I delivered exactly what was specified in the brief, client keeps changing requirements."</p>
              </div>
            </div>
            <div className="ai-processing">
              <span className="ai-arrow">↓</span>
              <span className="label">AI Agent analyzes evidence</span>
              <span className="ai-arrow">↓</span>
            </div>
            <div className="mini-verdict">
              <div className="mock-field"><span className="mock-label">PROPOSAL</span><span className="mock-value amber">Split Resolution</span></div>
              <div className="mock-field"><span className="mock-label">ALLOCATION</span><span className="mock-value">300 AED → Seller, 200 AED → Buyer</span></div>
              <div className="mock-field"><span className="mock-label">CLOSES WHEN</span><span className="mock-value">Both parties accept. Either can escalate to a human.</span></div>
            </div>
          </div>
        </div>
      )
    }
  ]

  return (
    <section className="how-it-works" id="how-it-works">
      <div className="container">
        <span className="label">The Full Journey</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>From handshake to resolution, step by step</h2>
        <p className="section-sub">TrustIQ covers the entire transaction lifecycle. The AI agent only intervenes when there is a real dispute.</p>

        <div className="steps-nav">
          {steps.map((s, i) => (
            <button
              key={i}
              className={`step-nav-btn ${activeStep === i ? 'active' : ''} ${i === 4 ? 'ai-step' : ''}`}
              onClick={() => setActiveStep(i)}
            >
              <span className="step-nav-num">{s.num}</span>
              <span className="step-nav-title">{s.subtitle}</span>
              {s.phase === 'v2' && <span className="step-nav-phase">v2</span>}
            </button>
          ))}
        </div>

        <div className="step-display">
          <div className="step-info">
            <span className="label">{steps[activeStep].subtitle}</span>
            <h3>{steps[activeStep].icon} {steps[activeStep].title}</h3>
            {steps[activeStep].phase === 'v2' && (
              <span className="phase-banner">Ships in v2, once a licensed payment partner is in place</span>
            )}
            <p>{steps[activeStep].description}</p>
            {activeStep < 4 && (
              <button className="step-next-btn" onClick={() => setActiveStep(activeStep + 1)}>
                Next: {steps[activeStep + 1].subtitle} →
              </button>
            )}
            {activeStep === 4 && (
              <a href="#resolution" className="step-next-btn">See a real resolution ↓</a>
            )}
          </div>
          <div className="step-visual-wrapper">
            {steps[activeStep].visual}
          </div>
        </div>
      </div>
    </section>
  )
}

function RealRun() {
  const r = RECORDED_RUN
  return (
    <section className="run" id="resolution">
      <div className="container">
        <span className="label">From the audit log</span>
        <h2 className="run-title">A resolution the system actually produced</h2>
        <p className="section-sub">
          This page used to render an invented answer behind a fake progress bar. The pipeline is
          real now, so what follows is a run that happened: the findings, the split and the numbers
          below are what the model returned, and the audit row is the row that recorded it. The
          dispute is a test case, not a customer&rsquo;s. The run is not.
        </p>

        <div className="run-grid">
          <div className="run-case">
            <h3>What was agreed</h3>
            <p className="run-terms">{r.contract.terms}</p>
            <p className="run-amount">{r.contract.amount}</p>

            <h3>What each side said</h3>
            <blockquote className="run-claim buyer">
              <span>Buyer</span>
              {r.buyerClaim}
            </blockquote>
            <blockquote className="run-claim seller">
              <span>Seller</span>
              {r.sellerClaim}
            </blockquote>
          </div>

          <div className="run-answer">
            <h3>What the agent found</h3>
            <ol className="run-findings">
              {r.findings.map((f) => <li key={f}>{f}</li>)}
            </ol>

            <div className="run-split">
              <div className="run-split-head">
                <span className="run-decision">{r.decision}</span>
                <span className="run-conf">confidence {r.audit.confidence}</span>
              </div>
              <div className="run-bar">
                <div className="run-bar-seller" style={{ width: r.split.sellerPct + '%' }} />
              </div>
              <div className="run-bar-legend">
                <span>Seller {r.split.seller}</span>
                <span>Buyer {r.split.buyer}</span>
              </div>
            </div>

            <p className="run-summary">{r.summary}</p>

            <dl className="run-audit">
              <div><dt>Model</dt><dd>{r.audit.model}</dd></div>
              <div><dt>Prompt</dt><dd>{r.audit.promptVersion}</dd></div>
              <div><dt>Latency</dt><dd>{r.audit.latency}</dd></div>
              <div><dt>Validation</dt><dd className="ok">{r.audit.outcome}</dd></div>
            </dl>
          </div>
        </div>

        <div className="run-refused">
          <h3>And two the system refused to pass on</h3>
          <p>
            These matter more than the one that worked. An agent that always answers is not
            trustworthy; one that knows when to stop is. Nothing unvalidated ever reaches either
            party, and every run is logged, including the failures.
          </p>
          <div className="run-refused-grid">
            {REFUSED_RUNS.map((x) => (
              <div className="run-refused-card" key={x.outcome}>
                <code>{x.outcome}</code>
                <p>{x.why}</p>
                <span className="run-refused-meta">
                  confidence {x.confidence} &middot; {x.latency}
                </span>
              </div>
            ))}
          </div>
        </div>

        <p className="run-note">
          A resolution only ends a dispute if <strong>both</strong> parties accept it. One refusal
          sends the case to a person. The agent proposes; it does not decide.
        </p>
      </div>
    </section>
  )
}

function App() {
  return (
    <>
      <Nav />
      <Hero />
      <Problem />
      <HowItWorks />
      <RealRun />
      <section className="problem" id="beta">
        <div className="container">
          <span className="label">Join the beta</span>
          <h2>Be told once, when the app opens</h2>
          <p className="section-sub">
            The app is built and not yet on either store. One email when that changes, and nothing
            else.
          </p>
          <div className="beta-wrap">
            <BetaForm source="home" />
          </div>
        </div>
      </section>
      <Footer />
    </>
  )
}

export default App
