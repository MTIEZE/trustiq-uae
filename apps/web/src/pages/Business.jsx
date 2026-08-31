import { Nav, Footer, BetaForm } from '../components/Shell.jsx'
import '../App.css'

/**
 * TrustIQ for a business.
 *
 * The honest version. There are no company accounts, no teams, no seats and no
 * admin for an organisation, so a page positioning TrustIQ as enterprise
 * software would be exactly the kind of claim the rest of this rebuild removed.
 *
 * What is true is that a very large share of UAE businesses are one person, and
 * the product serves that person well. So the page is addressed to them, and it
 * says plainly what a larger organisation would need and does not have.
 */

const FOR_YOU = [
  {
    title: 'The same client, every month',
    body: 'A contract can run for a period with a start, an end and a renewal you both agreed: none, decided together, or automatic. Both of you are warned two weeks before it runs out, and an automatic renewal rolls forward by its own length and is written down.',
  },
  {
    title: 'Work delivered in stages',
    body: 'Split a contract into stages with their own amounts and dates. Each is delivered, accepted or sent back on its own, and the last one accepted confirms the whole thing.',
  },
  {
    title: 'A record that outlives the relationship',
    body: 'Terms neither side can rewrite, documents fingerprinted on arrival, and every move timestamped with who made it. If it ends badly a year from now, the record is the same record.',
  },
  {
    title: 'A dispute that does not start from zero',
    body: 'Both accounts and the documents already filed go to the agent together. What comes back distinguishes the facts both sides agree on from the points that are contested and the ones nothing supports.',
  },
]

const NOT_BUILT = [
  ['One account, one person', 'There are no company accounts, no teams and no seats. Two people at the same firm are two accounts with no relationship between them.'],
  ['No delegation', 'You cannot have an assistant draft a contract you sign, or give a colleague read access to your agreements.'],
  ['No bulk anything', 'No import, no templates, no sending the same contract to thirty people. Every contract is written once.'],
  ['No integrations', 'No accounting software, no calendar, no API for your own systems.'],
]

export default function Business() {
  return (
    <>
      <Nav current="Business" />

      <section className="hero hero-narrow">
        <div className="container">
          <span className="label">TrustIQ for business</span>
          <h1>Built for the business that is one person</h1>
          <p className="hero-sub">
            Which, in the UAE, is a great many of them. A freelancer, a consultant, a small
            studio, a trader with regular customers. If that is you, the whole product is aimed at
            your situation.
          </p>
        </div>
      </section>

      <section className="part">
        <div className="container">
          <span className="label">What it does for you</span>
          <h2>Repeat work, without the paperwork getting worse</h2>
          <div className="pillar-grid">
            {FOR_YOU.map((f) => (
              <div className="pillar" key={f.title}>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="part part-alt">
        <div className="container">
          <span className="label">If you are larger than that</span>
          <h2>What is honestly not here</h2>
          <p className="section-sub">
            If your firm has staff, TrustIQ does not yet fit, and it is quicker to say so than to
            let you find out during a trial.
          </p>
          <dl className="gate-list">
            {NOT_BUILT.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
          <p className="run-note">
            None of that is hard to build; it is not built because nobody has needed it yet. If
            your organisation would, say so below and say what it would take. That is worth more
            than a guess, and it is how the list above gets shorter.
          </p>
        </div>
      </section>

      <section className="problem">
        <div className="container">
          <span className="label">Tell us what you need</span>
          <h2>The note field is the point</h2>
          <p className="section-sub">
            Leave your address and what your business would want from this. You will be told once
            when the app opens, and read properly in the meantime.
          </p>
          <div className="beta-wrap">
            <BetaForm source="business" />
          </div>
        </div>
      </section>

      <Footer />
    </>
  )
}
