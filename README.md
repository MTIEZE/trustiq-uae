# TrustIQ UAE

**Trust infrastructure for peer-to-peer transactions in the United Arab Emirates.**

TrustIQ turns a handshake between strangers into a tracked contract: agreed terms,
timestamped evidence, and a delivery lifecycle both sides can see. When a delivery
goes wrong, an AI agent reads the evidence and proposes a structured resolution
that both parties can accept or send to a human reviewer.

Target use cases: freelancer vs. client, merchant vs. buyer, and any P2P or small-SME
transaction that has no platform guarantee behind it.

## Product scope

**v1 does not hold funds.** Payment happens directly between the parties. This is a
deliberate choice: holding third-party funds in the UAE is a regulated activity
requiring a CBUAE licence or an equivalent DIFC/ADGM permission, and building the
contract, evidence and dispute layers first lets the product ship while that path is
worked out. Escrow arrives in v2 through a licensed payment partner.

The AI never rules. It issues a **proposal** that closes the dispute only when both
parties accept it; a single refusal escalates to a human reviewer.

## Repository layout

```
apps/web         Landing page and interactive walkthrough (React 19 + Vite)
packages/core    Domain logic: money, transaction and dispute lifecycles,
                 AI resolution contract. Pure TypeScript, no framework.
packages/ai      Dispute resolution pipeline: prompt, model call, validation,
                 escalation, audit trail.
packages/server  Evidence upload path and the resolution run. Written against
                 ports, so it runs in tests with no Supabase and no network.
supabase/        Postgres schema, migrations and SQL test suite
```

`packages/core` is deliberately framework-free so the same rules run unchanged in the
web app, the future mobile app, and on the server. It has no runtime dependencies.

## Commands

Run from the repository root.

```bash
npm install      # install all workspaces
npm run dev      # local dev server for the web app
npm test         # domain test suite (93 tests)
npm run test:db  # schema test suite against a throwaway Postgres (needs Docker)
npm run typecheck
npm run lint
npm run build    # build core, then the web app into apps/web/dist
```

CI runs lint, typecheck, tests and build on every pull request, plus the schema
suite in a second job. The GitHub Pages deploy runs the same gate before
publishing, so a failing domain test blocks release.

## Domain rules worth knowing before changing code

- **Money is an integer number of fils** (1 AED = 100 fils). Never a float. See
  `packages/core/src/money.ts`.
- **Splits must conserve the total exactly.** `allocate` uses the largest-remainder
  method and is tested to never lose or invent a fil.
- **State changes go through the machines.** `transaction-machine.ts` and
  `dispute-machine.ts` declare every legal move as a data table, including which
  party may make it. Anything absent from the table is refused.
- **The model's output is never trusted.** `validateProposal` rejects allocations
  that do not balance, decisions contradicting their own allocation, and findings
  citing evidence nobody submitted.
- **These rules exist twice on purpose**, in TypeScript and in SQL, so no client can
  talk the database into an illegal move. `schema-parity.test.ts` parses the
  migrations and fails if the two copies disagree. Change a transition on one side
  and you must change it on the other. See [supabase/README.md](supabase/README.md).
- **The model never computes money.** It returns a whole percentage to the seller
  and `splitByPercent` derives the fils, so no model output can lose or invent a
  fil. Judgment is the model's job; arithmetic is the code's.
- **Nothing the model returns reaches a party unvalidated.** Refusals, truncation,
  malformed output, hallucinated evidence citations, and low confidence all route
  to a human reviewer instead. Every run is written to the audit trail, failures
  included.
- **No audit record, no proposal.** If the audit write fails, the run escalates
  rather than showing the parties a resolution nobody could later explain.
- **The evidence digest is the server's.** Clients cannot insert evidence rows or
  write to the bucket; the upload path hashes the bytes it stores. A digest the
  uploader chose would prove nothing, and every grounded finding rests on it.

## Status

The landing page is live and reflects the product honestly, with escrow visibly
dated to v2. The domain layer and the database schema are built and tested. Not yet
built: the application backend, evidence storage, the mobile app, and escrow.

## Roadmap

1. Legal scoping with a UAE fintech firm. Confirm the no-funds v1 needs no licence.
2. Backend on Supabase: schema, row-level security, authentication.
3. Mobile app (React Native + Expo), contract and dispute flows, UAE Pass identity.
4. Store submission and a closed beta with freelancers in Dubai and Sharjah.
5. Escrow via a licensed partner, once usage numbers justify the negotiation.
