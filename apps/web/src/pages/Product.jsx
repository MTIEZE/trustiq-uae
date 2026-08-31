import { Nav, Footer, BetaForm } from '../components/Shell.jsx'
import '../App.css'

/**
 * What TrustIQ does, part by part.
 *
 * Every claim here is something in supabase/migrations. Where a thing is only
 * half built, it says so in the same paragraph rather than in a footnote: a
 * product page that has to be read carefully to find what is missing is a
 * product page that was written to be skimmed by somebody who will find out
 * later.
 */

const PARTS = [
  {
    id: 'agreements',
    kicker: 'Agreements',
    title: 'Written once, then fixed',
    body: 'A contract carries the terms, the amount to the fils, who is buying and who is selling, and optionally the stages the work is delivered in. While it is a draft its author can change anything. The moment it is sent, the database refuses an edit: not a disabled button, a policy that rejects the write.',
    detail: [
      ['Money is an integer', 'Amounts are stored in fils, never as a decimal. A split of a contract always adds back up to the contract, tested exhaustively.'],
      ['Stages, if the work has them', 'Each with its own amount and due date, and the total may not promise more than the contract is worth.'],
      ['A period, if it runs for one', 'Start, end, or open-ended, with a renewal the two of you agreed: none, decided together, or automatic.'],
    ],
  },
  {
    id: 'invitations',
    kicker: 'Invitations',
    title: 'For somebody who is not here yet',
    body: 'You do not need the other party to have an account before you write the contract. An invitation carries a readable code, expires after thirty days, can be withdrawn, and can be claimed exactly once. Claiming it checks the code and the address, because a code on its own is a bearer token.',
    detail: [
      ['One use', 'A claimed invitation cannot be claimed again, by anyone.'],
      ['The right person', 'The address is checked as well as the code, so a forwarded message is not a way in.'],
    ],
  },
  {
    id: 'verification',
    kicker: 'Verification',
    title: 'A contract binds two checked identities',
    body: 'Anybody can draft, send and file evidence. Making a contract binding requires both parties to be verified, and that is enforced when the acceptance is written rather than checked on a screen. Today a person does the checking; UAE Pass takes over when its Service Provider registration is through.',
    detail: [
      ['Four states, not two', 'Never asked, waiting, refused with a reason you can act on, verified. A refusal is not a dead end.'],
      ['On the record', 'What was looked at is written down and cannot be edited afterwards, including a verification that was later withdrawn.'],
    ],
  },
  {
    id: 'lifecycle',
    kicker: 'Lifecycle',
    title: 'Ten states, and nothing outside them',
    body: 'Draft, sent, active, delivered, confirmed, disputed, resolved, declined, cancelled, expired. Every legal move between them is a row in a table that says which state, which move, and which party may make it. Anything not in that table is refused, and the same table exists in three languages so the app, the server and the database cannot disagree.',
    detail: [
      ['Written three times on purpose', 'TypeScript, Dart and SQL, kept in step by a test that parses all three and fails if they differ.'],
      ['A log, not a column', 'Every move is appended with who made it and when. The current state is a consequence of the log, not a thing somebody set.'],
    ],
  },
  {
    id: 'disputes',
    kicker: 'Disputes',
    title: 'Both accounts, and what was filed',
    body: 'Either party can open a dispute on a contract that is active or delivered. Each side gives their account, and either can file documents. Every document is fingerprinted by the server as it arrives, from the bytes it stored, so the fingerprint is a fact rather than a claim the uploader made.',
    detail: [
      ['Append only', 'Evidence cannot be edited or removed once filed, by anybody, including with the service key.'],
      ['Text is read out', 'A document the system can read has its text extracted, so the agent reads what was filed rather than a filename.'],
    ],
  },
  {
    id: 'ai',
    kicker: 'Assistance',
    title: 'The agent proposes; it does not decide',
    body: 'When both accounts are in, a verified party can send the case to the model. It returns findings, a decision and a percentage; the split in fils is computed from that percentage rather than taken from the model, so no answer can lose or invent a fil. A proposal only ends the dispute if both parties accept it, and one refusal sends the case to a person.',
    detail: [
      ['Nothing unchecked reaches anybody', 'A refusal, a truncated answer, invalid JSON, a finding citing evidence that was never filed, or low confidence: each of these escalates instead of being shown.'],
      ['Every run is logged, including the failures', 'A model that often fails validation is a signal, and deleting the failures would hide it.'],
      ['What the parties wrote is not an instruction', 'Their text is fenced and the system prompt says it is material to weigh, not directions to follow.'],
    ],
  },
]

export default function Product() {
  return (
    <>
      <Nav current="Product" />

      <section className="hero hero-narrow">
        <div className="container">
          <span className="label">The product</span>
          <h1>Six parts, and what each one actually does</h1>
          <p className="hero-sub">
            Everything below is something in the schema. Where a piece is half built, it says so
            here rather than somewhere you would find later.
          </p>
        </div>
      </section>

      {PARTS.map((part, i) => (
        <section className={i % 2 ? 'part part-alt' : 'part'} id={part.id} key={part.id}>
          <div className="container part-grid">
            <div>
              <span className="label">{part.kicker}</span>
              <h2>{part.title}</h2>
              <p className="part-body">{part.body}</p>
            </div>
            <dl className="part-detail">
              {part.detail.map(([k, v]) => (
                <div key={k}>
                  <dt>{k}</dt>
                  <dd>{v}</dd>
                </div>
              ))}
            </dl>
          </div>
        </section>
      ))}

      <section className="problem">
        <div className="container">
          <span className="label">Join the beta</span>
          <h2>Be told once, when the app opens</h2>
          <div className="beta-wrap">
            <BetaForm source="product" />
          </div>
        </div>
      </section>

      <Footer />
    </>
  )
}
