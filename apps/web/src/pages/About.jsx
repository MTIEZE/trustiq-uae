import { Nav, Footer, BetaForm } from '../components/Shell.jsx'
import { useReveal } from '../lib/motion.js'
import '../App.css'
import '../motion.css'

/**
 * Why this exists.
 *
 * Structured so a team, a set of partners or a press section can be added
 * without rewriting it: each block is a section, and nothing depends on there
 * being exactly these ones.
 *
 * No stock photography of people in a meeting, no invented headcount, no
 * "founded in" for a thing that is a few months old. The two structural
 * decisions are the most interesting thing about the project, so they are the
 * middle of the page rather than a footnote.
 */

const DECISIONS = [
  {
    title: 'TrustIQ never holds your money',
    body: 'Holding other people’s funds in the UAE is a licensed activity, under the central bank or one of the financial centres. TrustIQ is not licensed for it and does not pretend to be, so payment happens directly between the two parties exactly as it does today.',
    consequence: 'What TrustIQ holds is the record. Nothing in the app can move a dirham, which is also why there is very little here worth stealing. Escrow arrives in a second version through a licensed partner, once there is enough real use to justify the conversation.',
  },
  {
    title: 'The agent proposes, it does not decide',
    body: 'A resolution only ends a dispute if both parties accept it. Either of them can refuse and ask for a person instead, and one refusal is enough.',
    consequence: 'That reduces the legal exposure of an automated decision to almost nothing, and it turns the quality of the model into a number that can be watched: how often people accept what it proposes. If they mostly refuse, the idea is wrong, and we will know rather than guess.',
  },
]

const FACTS = [
  ['Where', 'Sharjah and Dubai, for the UAE.'],
  ['When', 'Started as a competition entry in 2026, where it placed fourth out of more than three hundred.'],
  ['Who', 'One person, so far.'],
  ['Open', 'The whole thing is readable, including the tests and the migrations.'],
]

export default function About() {
  useReveal()

  return (
    <>
      <Nav current="About" />

      <section className="hero hero-narrow hero-about">
        <div className="container">
          <span className="label" data-reveal>About</span>
          <h1 data-reveal>Most agreements here are made without one</h1>
          <p className="hero-sub" data-reveal>
            A freelancer takes a brief over WhatsApp. A buyer pays a stranger for a phone. A small
            studio does three months of work on the strength of a call. When it goes well, none of
            that matters. When it does not, there is nothing to point at.
          </p>
        </div>
      </section>

      <section className="part">
        <div className="container part-grid">
          <div>
            <span className="label" data-reveal>The problem</span>
            <h2 data-reveal>Not the absence of contracts. The absence of a record.</h2>
            <p className="part-body" data-reveal>
              People do write things down. They write them in chat, in email, in a note that one
              of them can edit afterwards. What is missing is not the agreement, it is anything
              that fixes it: a version both sides accepted, evidence with a date nobody set by
              hand, and a way through a disagreement that does not start with hiring somebody.
            </p>
          </div>
          <div>
            <span className="label" data-reveal>The intent</span>
            <h2 data-reveal>A trust layer, not a marketplace</h2>
            <p className="part-body" data-reveal>
              TrustIQ does not find you work, take a cut of it, or stand between you and your
              client. It sits underneath an arrangement the two of you already have and makes it
              something you can both point at later. Nothing about it requires the other person to
              use TrustIQ for anything else, ever again.
            </p>
          </div>
        </div>
      </section>

      <section className="part part-alt">
        <div className="container">
          <span className="label" data-reveal>Two decisions</span>
          <h2 data-reveal>The choices that shaped everything else</h2>
          <div className="decisions">
            {DECISIONS.map((d) => (
              <article className="decision" data-reveal key={d.title}>
                <h3>{d.title}</h3>
                <p>{d.body}</p>
                <p className="decision-so">{d.consequence}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="part">
        <div className="container">
          <span className="label" data-reveal>Plainly</span>
          <h2 data-reveal>Where this actually is</h2>
          <dl className="gate-list" data-reveal>
            {FACTS.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
          <p className="run-note">
            It is early. The app is built and not yet on a store, the model has run a handful of
            times, and the number of people using it is small enough to count. That is worth
            saying on a page like this, because the alternative is the language every young
            company uses and nobody believes.
          </p>
        </div>
      </section>

      <section className="problem">
        <div className="container">
          <span className="label" data-reveal>Join the beta</span>
          <h2 data-reveal>Be told once, when the app opens</h2>
          <div className="beta-wrap" data-reveal>
            <BetaForm source="about" />
          </div>
        </div>
      </section>

      <Footer />
    </>
  )
}
