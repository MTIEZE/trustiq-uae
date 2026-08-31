import { Nav, Footer, StoreButtons, BetaForm } from '../components/Shell.jsx'
import { STORES_LIVE } from '../lib/site.js'
import '../App.css'

/**
 * Getting the app, which cannot be downloaded yet.
 *
 * The honest version of a download page. It says where the app is, what is
 * standing between it and a listing, and offers the only thing that is real
 * today: being told when that changes.
 *
 * In `pages/` rather than beside its entry point, because Windows filenames are
 * case-insensitive and `src/Download.jsx` next to `src/download.jsx` is one
 * file wearing two names. The first version of this silently overwrote itself.
 */

const WHAT_IT_DOES = [
  {
    title: 'Write down what was agreed',
    body: 'Terms, amount, who is who, and how long it runs. Once both of you accept it, neither side can change it.',
  },
  {
    title: 'File what happened',
    body: 'Documents are fingerprinted by the server as they arrive, so what you filed is what everybody sees later.',
  },
  {
    title: 'Ask for a resolution',
    body: 'When it goes wrong, an agent reads both accounts against the evidence and proposes a split. It only ends the dispute if you both accept it.',
  },
  {
    title: 'Both languages, both directions',
    body: 'English and Arabic throughout, right to left where it belongs, chosen on the device before there is an account.',
  },
]

const BEFORE_THE_STORES = [
  ['Identity', 'UAE Pass needs Service Provider registration. Until then a person checks, and the app has a real queue for it.'],
  ['Play listing', 'The data safety form, a content rating, screenshots, and a closed test with real testers.'],
  ['App Store', 'A developer account and a review. Not started, and it comes after Android.'],
]

export default function Download() {
  return (
    <>
      <Nav current="Get the app" />

      <section className="hero hero-narrow">
        <div className="container">
          <span className="label">The TrustIQ app</span>
          <h1>Not out yet, and here is exactly where it is</h1>
          <p className="hero-sub">
            The app is built and running. What it does not have is a listing on either store, and
            a button that pretends otherwise would be the first thing on this site that is not
            true.
          </p>
          <StoreButtons />
          {!STORES_LIVE && (
            <p className="hero-note">
              Both of those turn into real links the day the listings exist. Until then, the way in
              is the closed beta.
            </p>
          )}
        </div>
      </section>

      <section className="problem">
        <div className="container">
          <span className="label">Join the beta</span>
          <h2>Be told once, when it opens</h2>
          <p className="section-sub">
            No newsletter, no sequence, no third party. One email, when there is something to
            install.
          </p>
          <div className="beta-wrap">
            <BetaForm source="download" />
          </div>
        </div>
      </section>

      <section className="how-it-works">
        <div className="container">
          <span className="label">What is in it</span>
          <h2>What the app does today</h2>
          <div className="cards">
            {WHAT_IT_DOES.map((c) => (
              <div className="card" key={c.title}>
                <h3>{c.title}</h3>
                <p>{c.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="run">
        <div className="container">
          <span className="label">What is left</span>
          <h2 className="run-title">Between here and a listing</h2>
          <p className="section-sub">
            Written out rather than summarised as &ldquo;coming soon&rdquo;, because a date nobody
            explains is a date nobody believes.
          </p>
          <dl className="gate-list">
            {BEFORE_THE_STORES.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <Footer />
    </>
  )
}
