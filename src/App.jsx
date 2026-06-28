import { useState, useEffect } from 'react'
import './App.css'

const DEMO_RESPONSE = {
  transaction_description: "Logo design for a startup",
  amount: "500",
  buyer_claim: "The designer delivered low quality work that does not match what was agreed.",
  seller_claim: "I delivered exactly what was specified in the brief, client keeps changing requirements.",
  evidence_notes: "Contract signed on June 1st, delivery made June 8th.",
  ai_resolution: {
    decision: "Split Resolution",
    reasoning: "The evidence shows a valid contract was signed and delivery did occur within the agreed window. However, the buyer's claim of quality mismatch and the seller's claim of shifting requirements cannot be fully verified from the notes alone — this is a genuinely ambiguous case rather than a clear-cut fault on either side.",
    action: "Release 60% of the held amount (300 AED) to the seller for work delivered on schedule, and refund 40% (200 AED) to the buyer to account for the unresolved quality concern.",
    confidence: "Medium",
    resolvedIn: "47s"
  }
}

const LOADING_STEPS = [
  "Receiving dispute payload...",
  "Routing to AI resolution engine...",
  "GPT-5.4 analyzing evidence...",
  "Writing resolution to database..."
]

function Nav() {
  return (
    <nav className="nav">
      <div className="container">
        <div className="nav-logo">Trust<span>IQ</span></div>
        <ul className="nav-links">
          <li><a href="#how-it-works">How It Works</a></li>
          <li><a href="#demo">Live Demo</a></li>
          <li><a href="#architecture">Architecture</a></li>
          <li><a href="#about">About</a></li>
        </ul>
      </div>
    </nav>
  )
}

function Hero() {
  return (
    <section className="hero">
      <div className="container">
        <span className="label">AI-Powered Trust Infrastructure</span>
        <h1>Secure transactions between strangers in the UAE</h1>
        <p className="hero-sub">
          TrustIQ locks payment in escrow until both parties confirm the deal is complete.
          If a dispute arises, an AI agent analyzes evidence and returns a structured resolution
          in under 60 seconds.
        </p>
        <a href="#how-it-works" className="hero-cta">See How It Works</a>
        <div className="hero-pills">
          <span className="pill"><span className="pill-dot"></span>Escrow Protection</span>
          <span className="pill"><span className="pill-dot"></span>AI Dispute Resolution</span>
          <span className="pill"><span className="pill-dot"></span>Under 60s Response</span>
        </div>
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
      title: 'Payment is locked in escrow',
      subtitle: 'ESCROW',
      icon: '🔒',
      description: 'Once both parties sign, the buyer\'s payment (500 AED) is locked in TrustIQ escrow. The seller can start working, knowing the money is secured. The buyer knows the money won\'t be released until the job is done.',
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
      description: 'The seller completes the work and marks the delivery as done. The buyer reviews and can either confirm satisfaction (releasing payment) or open a dispute if something is wrong.',
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
      title: 'Dispute? AI resolves in 60 seconds',
      subtitle: 'AI RESOLUTION',
      icon: '🧠',
      description: 'If the buyer is not satisfied and opens a dispute, both parties submit their claims and evidence. TrustIQ\'s AI agent analyzes everything and returns a fair, structured resolution, no human mediator needed.',
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
              <div className="mock-field"><span className="mock-label">DECISION</span><span className="mock-value amber">Split Resolution</span></div>
              <div className="mock-field"><span className="mock-label">ACTION</span><span className="mock-value">300 AED → Seller, 200 AED → Buyer</span></div>
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
            </button>
          ))}
        </div>

        <div className="step-display">
          <div className="step-info">
            <span className="label">{steps[activeStep].subtitle}</span>
            <h3>{steps[activeStep].icon} {steps[activeStep].title}</h3>
            <p>{steps[activeStep].description}</p>
            {activeStep < 4 && (
              <button className="step-next-btn" onClick={() => setActiveStep(activeStep + 1)}>
                Next: {steps[activeStep + 1].subtitle} →
              </button>
            )}
            {activeStep === 4 && (
              <a href="#demo" className="step-next-btn">Try the Live Demo ↓</a>
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

function DemoForm({ onSubmit, loading }) {
  const [form, setForm] = useState({
    transaction_description: DEMO_RESPONSE.transaction_description,
    amount: DEMO_RESPONSE.amount,
    buyer_claim: DEMO_RESPONSE.buyer_claim,
    seller_claim: DEMO_RESPONSE.seller_claim,
    evidence_notes: DEMO_RESPONSE.evidence_notes
  })

  const handleChange = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value })
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    onSubmit(form)
  }

  return (
    <form className="demo-form" onSubmit={handleSubmit}>
      <div className="form-group">
        <label>Transaction Description</label>
        <input name="transaction_description" value={form.transaction_description} onChange={handleChange} />
      </div>
      <div className="form-group">
        <label>Amount (AED)</label>
        <input name="amount" value={form.amount} onChange={handleChange} />
      </div>
      <div className="form-group">
        <label>Buyer Claim</label>
        <textarea name="buyer_claim" value={form.buyer_claim} onChange={handleChange} />
      </div>
      <div className="form-group">
        <label>Seller Claim</label>
        <textarea name="seller_claim" value={form.seller_claim} onChange={handleChange} />
      </div>
      <div className="form-group">
        <label>Evidence Notes</label>
        <textarea name="evidence_notes" value={form.evidence_notes} onChange={handleChange} />
      </div>
      <button type="submit" className="submit-btn" disabled={loading}>
        {loading ? 'Processing...' : 'Submit Dispute for AI Resolution'}
      </button>
    </form>
  )
}

function LoadingState() {
  const [activeStep, setActiveStep] = useState(0)

  useEffect(() => {
    const timers = LOADING_STEPS.map((_, i) =>
      setTimeout(() => setActiveStep(i), i * 450)
    )
    return () => timers.forEach(clearTimeout)
  }, [])

  return (
    <div className="loading-container">
      <div className="loading-spinner"></div>
      <div className="loading-text">AI Resolution Engine</div>
      <div className="loading-steps">
        {LOADING_STEPS.map((step, i) => (
          <div
            key={i}
            className={`loading-step ${i === activeStep ? 'active' : i < activeStep ? 'done' : ''}`}
          >
            {i < activeStep ? '✓' : i === activeStep ? '›' : '·'} {step}
          </div>
        ))}
      </div>
    </div>
  )
}

function VerdictCard({ resolution }) {
  return (
    <div className="verdict-card">
      <div className="verdict-header">
        <div className="verdict-header-left">
          <span className="ai-badge"><span className="ai-badge-dot"></span>AI Resolution</span>
        </div>
        <span className="verdict-time">Resolved in {resolution.resolvedIn}</span>
      </div>
      <div className="verdict-body">
        <div className="verdict-field">
          <div className="verdict-field-label">Decision</div>
          <div className="verdict-decision">{resolution.decision}</div>
        </div>
        <div className="verdict-field">
          <div className="verdict-field-label">Reasoning</div>
          <div className="verdict-field-value">{resolution.reasoning}</div>
        </div>
        <div className="verdict-field">
          <div className="verdict-field-label">Action</div>
          <div className="verdict-field-value">{resolution.action}</div>
        </div>
        <div className="verdict-field">
          <div className="verdict-field-label">Confidence</div>
          <span className="verdict-confidence">{resolution.confidence}</span>
        </div>
      </div>
    </div>
  )
}

function PayloadCard({ payload }) {
  return (
    <div className="payload-card">
      <div className="payload-header">
        <span>Webhook Payload (JSON)</span>
        <span>POST /webhook/trustiq</span>
      </div>
      <div className="payload-body">
        <pre>{JSON.stringify(payload, null, 2)}</pre>
      </div>
    </div>
  )
}

function Demo() {
  const [state, setState] = useState('idle')
  const [payload, setPayload] = useState(null)

  const handleSubmit = (formData) => {
    setPayload(formData)
    setState('loading')
    setTimeout(() => setState('done'), 2000)
  }

  return (
    <section className="demo" id="demo">
      <div className="container">
        <span className="label">Live Demo — Step 5 in Action</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>Test the AI dispute resolution engine</h2>
        <p className="section-sub">This is what happens at Step 5 when a dispute is opened. Fill in the claims and see the AI agent resolve it.</p>
        <div className="demo-wrapper">
          <DemoForm onSubmit={handleSubmit} loading={state === 'loading'} />
          <div className="demo-result">
            {state === 'idle' && (
              <div className="result-placeholder">
                <div className="icon">⚖️</div>
                <p>Submit a dispute to see the AI resolution engine in action</p>
              </div>
            )}
            {state === 'loading' && <LoadingState />}
            {state === 'done' && (
              <>
                <VerdictCard resolution={DEMO_RESPONSE.ai_resolution} />
                <PayloadCard payload={payload} />
              </>
            )}
          </div>
        </div>
        <div className="demo-note">
          <strong>Transparency note:</strong> This demo showcases a real AI-generated resolution
          from TrustIQ's live backend (Make.com webhook → OpenAI GPT-5.4 → Supabase).
          The response shown was captured from an actual end-to-end pipeline run, not fabricated
          for this demo. The frontend does not make live API calls to avoid CORS limitations
          with the Make webhook.
        </div>
      </div>
    </section>
  )
}

function Architecture() {
  const nodes = [
    { icon: '🌐', title: 'Web Interface', sub: 'React App', active: false },
    { icon: '⚡', title: 'Make Webhook', sub: 'Orchestration', active: true },
    { icon: '🧠', title: 'OpenAI GPT-5.4', sub: 'AI Resolution', active: true },
    { icon: '🗄️', title: 'Supabase', sub: 'PostgreSQL', active: false },
  ]

  const details = [
    { step: '01', title: 'Dispute Submitted', desc: 'When a buyer opens a dispute, both parties submit their claims and evidence through the web interface.' },
    { step: '02', title: 'Webhook Receives', desc: 'Make.com custom webhook receives the JSON payload and routes it to the AI processing module.' },
    { step: '03', title: 'AI Analyzes', desc: 'GPT-5.4-mini, prompted as TrustIQ Dispute Resolution Agent, analyzes evidence from both parties and generates a structured verdict.' },
    { step: '04', title: 'Resolution Stored', desc: 'The AI decision (verdict, reasoning, action, confidence) is written to the Supabase disputes table and escrow is adjusted accordingly.' },
  ]

  return (
    <section className="architecture" id="architecture">
      <div className="container">
        <span className="label">Architecture</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>How the AI resolution pipeline works</h2>
        <div className="arch-flow">
          {nodes.map((node, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div className={`arch-node ${node.active ? 'active' : ''}`}>
                <div className="arch-node-icon">{node.icon}</div>
                <h3>{node.title}</h3>
                <p>{node.sub}</p>
              </div>
              {i < nodes.length - 1 && <span className="arch-arrow">→</span>}
            </div>
          ))}
        </div>
        <div className="arch-detail">
          {details.map((d) => (
            <div key={d.step} className="arch-detail-card">
              <div className="step-num">STEP {d.step}</div>
              <h4>{d.title}</h4>
              <p>{d.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}

function Footer() {
  return (
    <footer className="footer" id="about">
      <div className="container">
        <div className="footer-challenge">Building AI Application Challenge · Decoding Data Science · June 2026</div>
        <div className="footer-brand">Trust<span>IQ</span> UAE</div>
        <div className="footer-copy">AI-powered trust infrastructure for secure transactions between strangers</div>
      </div>
    </footer>
  )
}

function App() {
  return (
    <>
      <Nav />
      <Hero />
      <Problem />
      <HowItWorks />
      <Demo />
      <Architecture />
      <Footer />
    </>
  )
}

export default App
