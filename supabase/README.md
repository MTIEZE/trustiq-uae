# TrustIQ database schema

Postgres schema for Supabase. Migrations apply in filename order.

```
migrations/
  0001_foundation.sql   schema, enums, the fils money domain, shared triggers
  0002_profiles.sql     users and identity verification
  0003_transactions.sql contracts, milestones, transition table, audit log
  0004_evidence.sql     the evidence vault, append-only and hash-pinned
  0005_disputes.sql     disputes, AI proposals, grounded findings, acceptance
  0006_ai_audit.sql     full model call trail, service role only
  0007_evidence_storage.sql
                        private evidence bucket; evidence rows and stored
                        objects both become server-written only

tests/
  00_supabase_stubs.sql  local-only stubs for auth, storage and the roles
  schema.test.sql        56 assertions run against a real Postgres
```

## Running the tests

Needs Docker and nothing else. No Supabase CLI, no local Postgres.

```bash
npm run test:db
```

It starts `postgres:16-alpine`, applies the stubs, applies every migration in
order, runs the assertions, and removes the container. It exits non-zero on the
first failure, and runs in CI on every pull request.

`00_supabase_stubs.sql` is **not** a migration. Supabase already provides
`auth.users`, `auth.uid()` and the `anon` / `authenticated` / `service_role`
roles; a bare Postgres container does not. Applying the stubs first means the
migrations under test are the exact files that ship.

## The rules this schema enforces

The domain rules live in two places: `packages/core` in TypeScript, so the apps
can reason offline, and here in SQL, so no client can talk the database into an
illegal move. `packages/core/src/schema-parity.test.ts` parses these migrations
and fails if the two ever disagree.

**Money never floats.** Every amount is a `bigint` in the `fils` domain
(1 AED = 100 fils), bounded to the same ceiling as `MAX_FILS` in TypeScript. A
schema test scans for any `*_fils` column that is not an integer type.

**State changes go through one door.** `transactions.state` and
`disputes.state` cannot be written directly: a trigger refuses any UPDATE that
changes them outside `apply_transaction_event()` / `apply_dispute_event()`.
Those functions validate against `app.transaction_transitions` and
`app.dispute_transitions`, which hold the same rows as the TypeScript tables.

**The actor is derived, never declared.** A caller cannot name its own role. The
functions resolve buyer, seller or system from `auth.uid()` against the contract,
so a client cannot confirm a delivery on the counterparty's behalf.

**The AI proposes, it does not rule.** `accept_proposal` is a system-only
transition. A party accepts through `accept_resolution_proposal()`, which writes
a row keyed `(proposal_id, role)`, so a replayed request is a duplicate key
rather than a second vote, and fires the closing transition only once two
distinct roles have accepted the same proposal.

**Model output cannot be malformed.** A proposal whose allocation does not sum
to the disputed amount fails a CHECK. A decision contradicting its own numbers
fails a CHECK. A finding citing evidence nobody submitted fails a foreign key. A
finding citing nothing at all fails a deferred constraint trigger at commit.

**The record cannot be rewritten.** Evidence, both audit logs, proposals and
acceptances are append-only, enforced by a trigger that fires even for roles
that bypass RLS.

**Every table has RLS.** A schema test fails if any table in `public` is missing
it, so a new table cannot ship open by default. `ai_call_log` deliberately has
RLS on and no client policy: prompts and raw model output stay internal.

## Applying to a Supabase project

With the Supabase CLI linked to your project:

```bash
supabase db push
```

Or paste each migration into the SQL editor in filename order. Do not apply
anything in `tests/`.

**The evidence digest cannot be chosen by the uploader.** 0007 removes the
client INSERT policy on `evidence` and grants no write policy on the storage
bucket, so rows and objects are both written only by the upload path in
`packages/server`, which hashes the bytes it stores. Without both halves a party
could either pick the digest or swap the file after it was recorded.

## Not in this schema yet

- **Escrow.** v1 does not hold funds. Where the states belong is marked
  `ESCROW-V2` in `0001_foundation.sql`.
- **HTTP endpoints.** `packages/server` holds the upload and resolution flows
  behind ports; the Supabase-backed adapters and the routes that call them are
  still to be written.
