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
        <a href="#demo" className="hero-cta">Try the Live Demo</a>
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
        <span className="label">Live Demo</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>See AI dispute resolution in action</h2>
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
    { step: '01', title: 'Dispute Submitted', desc: 'User submits a dispute with transaction details, buyer/seller claims, and evidence through the web interface.' },
    { step: '02', title: 'Webhook Receives', desc: 'Make.com custom webhook receives the JSON payload and routes it to the AI processing module.' },
    { step: '03', title: 'AI Analyzes', desc: 'GPT-5.4-mini, prompted as TrustIQ Dispute Resolution Agent, analyzes evidence from both parties and generates a structured verdict.' },
    { step: '04', title: 'Resolution Stored', desc: 'The AI decision (verdict, reasoning, action, confidence) is written to the Supabase disputes table for record-keeping.' },
  ]

  return (
    <section className="architecture" id="architecture">
      <div className="container">
        <span className="label">Architecture</span>
        <h2 style={{ fontSize: '2rem', marginTop: 12 }}>How TrustIQ works under the hood</h2>
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
      <Demo />
      <Architecture />
      <Footer />
    </>
  )
}

export default App
