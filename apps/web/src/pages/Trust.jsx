import { Nav, Footer, BetaForm } from '../components/Shell.jsx'
import '../App.css'

/**
 * How it is built, written from the schema.
 *
 * The hard rule for this page: nothing on it may be a claim that cannot be
 * pointed at. No certifications that were never obtained, no "bank-grade
 * security", no badges. The last section says what is not built, because a
 * security page with no such section is a security page nobody should believe.
 */

const ENFORCED = [
  {
    title: 'Row level security on every table',
    body: 'Not a filter in the application. Postgres decides what a query may see, using the identity in the token, and a test sweeps every table in the schema to check none was created without it.',
  },
  {
    title: 'The actor comes from the token',
    body: 'No function accepts "who I am" as an argument. It is read from the session, so acting as the other party is not a request anybody can make.',
  },
  {
    title: 'The key in the app opens nothing',
    body: 'The publishable key ships inside the app, so anything it can call is a public endpoint. A sweep asserts that no function in the public schema is callable with it, and the live project is asked the same question every day.',
  },
  {
    title: 'Records that cannot be rewritten',
    body: 'Evidence, contract moves, dispute moves, identity checks and every model run are append-only, held by triggers that refuse an update or a delete even for the service key.',
  },
  {
    title: 'Separate powers, separate lists',
    body: 'Reviewing a dispute, reading the platform numbers and verifying an identity are three different authorities held on three different lists. Being on one grants nothing on the others, and none of the lists is writable through any API.',
  },
  {
    title: 'Deleting an account means it',
    body: 'An account nothing points at is deleted outright. One a contract points at is emptied, because the other party keeps their copy of an agreement they made; the tombstone address is a reserved domain, so nothing can ever be posted to it.',
  },
]

const CHECKED = [
  ['Identity', 'A person checks a document and writes down what they saw. Not an automated KYC provider, and not a database of scanned IDs: no copy of your document is stored on our servers.'],
  ['Evidence', 'Fingerprinted by the server from the bytes it stored, so the fingerprint is a fact rather than something the uploader asserted.'],
  ['The model', 'Its output is validated before anybody sees it: the split has to add up, the decision has to agree with its own numbers, and a finding may not cite a document that does not exist.'],
]

const NOT_YET = [
  ['No certification', 'TrustIQ holds no security certification and this page will not imply one. When there is an audit to point at, it will be named here with its date.'],
  ['No penetration test', 'The database rules are covered by 343 assertions run against a real Postgres on every change, which is not the same thing as somebody trying to break in.'],
  ['Failed sign-ins are not recorded', 'Successful ones are, and so is every action on a contract or a dispute. Attempted sign-ins live in the platform’s own logs, outside our schema; bringing them in is work that has not been done.'],
  ['No escrow, and so no funds to lose', 'TrustIQ never holds money. That is a licensing decision rather than a security one, but it is the largest single reason there is little here worth stealing.'],
]

export default function Trust() {
  return (
    <>
      <Nav current="Trust" />

      <section className="hero hero-narrow">
        <div className="container">
          <span className="label">Trust and security</span>
          <h1>What is enforced, what is checked, and what is not built</h1>
          <p className="hero-sub">
            A product about trust should be specific about its own. Everything on this page can be
            pointed at in the schema, and the last section is the one worth reading.
          </p>
        </div>
      </section>

      <section className="part">
        <div className="container">
          <span className="label">Enforced</span>
          <h2>Held by the database, not by the screen</h2>
          <p className="section-sub">
            A rule in an application is a suggestion to anybody holding a terminal. These are
            refusals from Postgres.
          </p>
          <div className="pillar-grid">
            {ENFORCED.map((e) => (
              <div className="pillar" key={e.title}>
                <h3>{e.title}</h3>
                <p>{e.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="part part-alt">
        <div className="container">
          <span className="label">Checked</span>
          <h2>Things a person or a rule looks at</h2>
          <dl className="gate-list">
            {CHECKED.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <section className="part">
        <div className="container">
          <span className="label">Not yet</span>
          <h2>What TrustIQ does not have</h2>
          <p className="section-sub">
            Every security page has this list. Most of them leave it out, which is the reason to
            put it in.
          </p>
          <dl className="gate-list">
            {NOT_YET.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
          <p className="run-note">
            The whole thing is readable. Every rule described here is in{' '}
            <a href="https://github.com/MTIEZE/trustiq-uae">the repository</a>, along with the
            tests that hold it, and <a href="/trustiq-uae/privacy.html">the privacy policy</a> was
            written from the same schema rather than from a template.
          </p>
        </div>
      </section>

      <section className="problem">
        <div className="container">
          <span className="label">Join the beta</span>
          <h2>Be told once, when the app opens</h2>
          <div className="beta-wrap">
            <BetaForm source="trust" />
          </div>
        </div>
      </section>

      <Footer />
    </>
  )
}
