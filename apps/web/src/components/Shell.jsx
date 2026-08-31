import { useState } from 'react'
import { STORES, joinBeta } from '../lib/site.js'

/**
 * The navigation and footer, shared by every page.
 *
 * They were inside App.jsx when there was one page. There are several now, and
 * a second copy of a navigation bar is a navigation bar that will disagree with
 * the first one within a month.
 */

const LINKS = [
  { href: '/trustiq-uae/#how-it-works', label: 'How it works' },
  { href: '/trustiq-uae/#resolution', label: 'Resolution' },
  { href: '/trustiq-uae/download.html', label: 'Get the app' },
]

export function Nav({ current }) {
  return (
    <nav className="nav">
      <div className="container nav-inner">
        <a className="nav-logo" href="/trustiq-uae/">Trust<span>IQ</span></a>
        <ul className="nav-links">
          {LINKS.map((l) => (
            <li key={l.href}>
              <a href={l.href} aria-current={current === l.label ? 'page' : undefined}>
                {l.label}
              </a>
            </li>
          ))}
        </ul>
      </div>
    </nav>
  )
}

export function Footer() {
  return (
    <footer className="footer" id="about">
      <div className="container">
        <div className="footer-top">
          <div>
            <a className="nav-logo" href="/trustiq-uae/">Trust<span>IQ</span></a>
            <p className="footer-line">
              A trust layer for agreements between people who have no platform standing behind
              them. Built in Sharjah, for the UAE.
            </p>
          </div>
          <ul className="footer-links">
            <li><a href="/trustiq-uae/download.html">Get the app</a></li>
            <li><a href="/trustiq-uae/privacy.html">Privacy</a></li>
            <li><a href="/trustiq-uae/delete-account.html">Delete your account</a></li>
            <li><a href="https://github.com/MTIEZE/trustiq-uae">Source</a></li>
          </ul>
        </div>
        <p className="footer-note">
          TrustIQ does not hold money. Payment is between the two parties, and holding funds in the
          UAE is a licensed activity TrustIQ is not licensed for. Escrow arrives in v2 through a
          licensed partner.
        </p>
      </div>
    </footer>
  )
}

/**
 * The two store buttons, in whatever state is true today.
 *
 * They read `STORES` rather than being written twice, so the day a listing
 * exists one line in site.js turns both of them on everywhere at once. Until
 * then they are labelled and inert: a button that looks live and goes nowhere
 * is a broken promise, and this site is arguing that TrustIQ keeps them.
 */
export function StoreButtons() {
  return (
    <div className="stores">
      {[
        { key: 'appStore', label: 'App Store', sub: 'Download on the' },
        { key: 'googlePlay', label: 'Google Play', sub: 'Get it on' },
      ].map((s) => {
        const href = STORES[s.key]
        const inner = (
          <>
            <span className="store-sub">{href ? s.sub : 'Coming to'}</span>
            <span className="store-name">{s.label}</span>
          </>
        )
        return href ? (
          <a className="store" key={s.key} href={href}>{inner}</a>
        ) : (
          <span className="store store-off" key={s.key} aria-disabled="true">{inner}</span>
        )
      })}
    </div>
  )
}

/**
 * Joining the beta.
 *
 * Says what happened either way. The one failure a person can do something
 * about is a malformed address, so that is the only one with its own sentence;
 * everything else says the same thing, because "HTTP 500" is not a sentence.
 */
export function BetaForm({ source, compact = false }) {
  const [email, setEmail] = useState('')
  const [note, setNote] = useState('')
  const [trap, setTrap] = useState('')
  const [state, setState] = useState({ kind: 'idle' })

  async function submit(e) {
    e.preventDefault()
    if (state.kind === 'sending') return

    // A field nobody can see and no person will fill. The cheapest thing that
    // works against the only abuse this form will realistically see.
    if (trap) {
      setState({ kind: 'done' })
      return
    }

    setState({ kind: 'sending' })
    const result = await joinBeta({ email, note, source })
    setState(
      result.ok
        ? { kind: 'done' }
        : { kind: 'error', reason: result.reason },
    )
  }

  if (state.kind === 'done') {
    return (
      <div className="beta-done">
        <strong>You are on the list.</strong>
        <p>
          You will hear from us once, when the app is out. Not a newsletter, and nobody else gets
          this address.
        </p>
      </div>
    )
  }

  return (
    <form className={compact ? 'beta beta-compact' : 'beta'} onSubmit={submit}>
      <div className="beta-row">
        <label className="sr-only" htmlFor={`beta-email-${source}`}>Email</label>
        <input
          id={`beta-email-${source}`}
          type="email"
          required
          placeholder="you@example.ae"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <button type="submit" disabled={state.kind === 'sending'}>
          {state.kind === 'sending' ? 'Sending' : 'Join the beta'}
        </button>
      </div>

      {!compact && (
        <textarea
          rows={2}
          maxLength={500}
          placeholder="Optional: what you would use it for"
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
      )}

      <input
        className="beta-trap"
        tabIndex={-1}
        autoComplete="off"
        aria-hidden="true"
        value={trap}
        onChange={(e) => setTrap(e.target.value)}
      />

      {state.kind === 'error' && (
        <p className="beta-error">
          {state.reason === 'email'
            ? 'That does not look like an email address.'
            : 'That did not go through. Nothing was saved, and you can try again.'}
        </p>
      )}

      <p className="beta-small">
        One email when the app opens. Nothing else, and no third party.
      </p>
    </form>
  )
}
