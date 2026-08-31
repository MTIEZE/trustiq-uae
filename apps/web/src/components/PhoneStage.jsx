import { useTilt } from '../lib/motion.js'

/**
 * The download page's centrepiece: the app, in space, with the things it
 * produces floating around it.
 *
 * Real 3D, in the sense that matters here: a perspective, a stack of planes at
 * different depths, and a pointer that moves the whole camera. What it is not
 * is WebGL. A 3D library for four rectangles would cost more to download than
 * every other asset on this site put together, on a page whose entire job is to
 * make somebody want to install something. CSS transforms are composited on the
 * GPU, weigh nothing, and are the reason this holds sixty frames on a phone.
 *
 * The floating pieces are states the app actually has. A verification that was
 * granted, a document whose fingerprint was taken, a proposal waiting on both
 * signatures. Nothing here is a badge TrustIQ has not earned, and the
 * resolution card says out loud that one refusal is enough to stop it.
 */

const SATELLITES = [
  {
    key: 'verified',
    depth: 2.4,
    className: 'sat sat-verify',
    mark: '✓',
    title: 'Identity verified',
    body: 'Checked by a person, on 30 August',
  },
  {
    key: 'evidence',
    depth: 1.7,
    className: 'sat sat-evidence',
    title: 'Evidence filed',
    body: 'brief-v2.pdf',
    code: 'sha256 9f2c…41ab',
  },
  {
    key: 'resolution',
    depth: 2.9,
    className: 'sat sat-resolution',
    title: 'Resolution proposed',
    body: '65 / 35',
    foot: 'Ends the dispute only if both accept',
  },
  {
    key: 'agreement',
    depth: 1.3,
    className: 'sat sat-agreement',
    title: 'Both parties accepted',
    body: 'Logo design · 500.00 AED',
  },
]

export default function PhoneStage() {
  const stage = useTilt()

  return (
    <div className="stage" ref={stage} aria-hidden="true">
      <div className="stage-glow" />
      <div className="stage-grid" />

      <div className="stage-phone" style={{ '--depth': 1 }}>
        <picture>
          <source
            srcSet="/trustiq-uae/app/contracts-dark.png"
            media="(prefers-color-scheme: dark)"
          />
        {/* Eager: this is the centrepiece of the page it is on, a few hundred
            pixels below the fold at most. Lazy meant it arrived as a hole. */}
          <img
            src="/trustiq-uae/app/contracts-light.png"
            alt=""
            width="390"
            height="800"
            loading="eager"
            decoding="async"
          />
        </picture>
      </div>

      {SATELLITES.map((s) => (
        <div className={s.className} key={s.key} style={{ '--depth': s.depth }}>
          <div className="sat-head">
            {s.mark && <span className="sat-mark">{s.mark}</span>}
            <strong>{s.title}</strong>
          </div>
          <span className="sat-body">{s.body}</span>
          {s.code && <code>{s.code}</code>}
          {s.foot && <span className="sat-foot">{s.foot}</span>}
        </div>
      ))}
    </div>
  )
}
