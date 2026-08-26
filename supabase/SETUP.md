# Setting up the Supabase project

Written to be followed in order. Steps 1 and 2 are decisions that are painful
to reverse; the rest are not.

## 1. Before creating the project: the region

**The region is fixed when the project is created.** Changing it later means
creating a second project and migrating the data across.

Two things bear on the choice:

- **Latency.** Users are in the UAE. The closest region Supabase offers wins on
  responsiveness.
- **Data residency.** TrustIQ will hold identity-verification results and, in
  v2, records tied to payments. UAE data protection law and the CBUAE/DIFC/ADGM
  regimes may require that this data stays in the country. **This is a question
  for the fintech lawyer, not a preference.** If the answer is yes and Supabase
  has no UAE region, that decides the hosting question for you, and it is much
  cheaper to learn now than after launch.

I could not confirm whether Supabase currently offers a Middle East region. The
region dropdown in the project-creation dialog is authoritative — read it there.
AWS itself has `me-central-1` in the UAE, so if Supabase does not, self-hosting
Supabase on AWS in that region is the fallback worth pricing.

If residency is not yet settled and you want to keep moving, create the project
in the closest available region and treat it as the development project, not the
one that will hold real user data.

## 2. Create the project

Note the **project ref** (the subdomain in the URL) and the **database
password**. Store the password in a password manager, not in this repository.

## 3. Apply the schema

From the repository root, with the Supabase CLI linked to the project:

```bash
supabase link --project-ref your-project-ref
supabase db push
```

The migrations in `supabase/migrations` apply in filename order. Do **not**
apply anything in `supabase/tests` — those are local-only stubs and assertions.

`0007_evidence_storage.sql` creates the private `evidence` bucket and its
policies as part of the push. There is no bucket to create by hand.

## 4. Check the schema landed as intended

In the SQL editor:

```sql
-- Every table in public must have row level security on.
select c.relname
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
-- Expect zero rows.

-- Evidence must not be insertable by clients.
select count(*) from pg_policies
where schemaname = 'public' and tablename = 'evidence' and cmd = 'INSERT';
-- Expect 0.

-- The bucket must be private.
select id, public from storage.buckets where id = 'evidence';
-- Expect public = false.
```

These three are the ones worth checking by hand, because each is a rule the
whole product leans on and none of them fails loudly if it is missing.

`npm run test:db` runs the full suite of 75 assertions against a throwaway
Postgres, so a failure there means the migrations are wrong rather than the
project being misconfigured.

## 5. Keys

From **Project Settings > API Keys**. Two keys, and they are not interchangeable.
On newer projects they are labelled "publishable" and "secret"; the roles and
the risks are the same.

| Key | Where it goes | What it can do |
| --- | --- | --- |
| `anon` | The Flutter and web apps | Only what RLS allows the signed-in user |
| `service_role` | A server process, and nowhere else | Everything, for everyone, ignoring RLS |

Copy `.env.example` to `.env` and fill in `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`. `.env` is gitignored.

**The service-role key must never reach a device.** It is not a stricter
version of the anon key; it turns off the schema's protections entirely. In a
Flutter build or a web bundle it is readable by anyone who downloads the app,
and every contract, dispute and document in the system is readable with it.

If it is ever committed or shipped, rotate it in the dashboard immediately.
Treat it as compromised from the moment it left your machine, not from the
moment someone proves they used it.

## 6. Authentication

The schema keys `profiles.id` to `auth.users.id`, so whichever sign-in methods
you enable, a profile row must be created for each new user. Email/password or
phone OTP both work; UAE Pass is a separate integration and does not replace
Supabase Auth (see `apps/mobile/lib/data/identity_provider.dart`).

Identity verification columns on `profiles` are server-written only. The RLS
policy re-reads the stored row on update, so a user cannot mark themselves
verified even with a valid session.

## 7. Deploying the Edge Function

Two functions: `file-evidence` files a document against a contract, and
`resolve-dispute` runs one dispute through the resolution pipeline. Both need
the Supabase CLI and a **personal access token with full access**.

Read-only tokens are the trap here. They pass `supabase projects list` and every
other read, then fail the deploy with a 403 that talks about privileges rather
than about the token:

```
unexpected create function status 403: Your account does not have the
necessary privileges to access this endpoint.
```

Generate the token at https://supabase.com/dashboard/account/tokens and choose
full access, not read-only. Put it in `.env` as `SUPABASE_ACCESS_TOKEN`, with no
space after the `=`.

```bash
export SUPABASE_ACCESS_TOKEN=...            # or read it from .env
./scripts/vendor-shared.sh                  # builds and copies the packages the function imports
npx supabase functions deploy file-evidence   --project-ref your-project-ref
npx supabase functions deploy resolve-dispute --project-ref your-project-ref
```

The vendoring step is not optional. Edge Functions are bundled from their own
directory and cannot reach into the npm workspace, so the compiled packages are
copied next to the function. Skip it and the function deploys against whatever
the last build left behind.

`file-evidence` needs no secret beyond what the platform injects.
`resolve-dispute` needs one more.

Then set the secret it reads. `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_ANON_KEY` are injected by the
platform; the model key is not:

```bash
npx supabase secrets set ANTHROPIC_API_KEY=... --project-ref your-project-ref
```

Run that in a terminal, not in a committed file.

## 8. Proving it works, without spending model budget

Two scripts, in this order. Both read `.env` and print no keys.

```bash
node scripts/seed-live-dispute.mjs      # builds a real contract, evidence and dispute
node scripts/dry-run-resolution.mjs     # runs the pipeline with a stub model
```

The seed script drives the real code: contracts move through
`apply_transaction_event`, evidence goes through `uploadEvidence` with the
Supabase adapters, and every rule the schema enforces gets a chance to refuse.

The dry run is the whole resolution pipeline with only `ModelClient` replaced.
It proves the parts a unit test cannot reach: that the live database accepts the
writes, that the transitions are legal in the order the pipeline fires them, and
that an audit row lands. It says nothing about the quality of a real model's
judgment, and the `model_id` it stores says `stub:dry-run/...` so a proposal
written this way is never mistaken for a real one.

`--refuse`, `--invent-evidence` and `--unsure` exercise the escalation branches.
A dispute resolves once, so re-seed between runs.

The third script drives `file-evidence` over real HTTP:

```bash
npx deno run -A --env-file=.env --config supabase/functions/deno.json   supabase/functions/file-evidence/index.ts     # in one terminal
node scripts/test-file-evidence.mjs http://127.0.0.1:8000
```

Running the function directly under Deno is deliberate. `supabase functions
serve` needs the whole local stack, which would point the function at a local
database and prove nothing about the real one. Run this way it talks to the
live project with real sessions, so the 26 checks cover what no unit test can:
multipart parsing, the caller's identity coming from their verified token
rather than the request body, the status code behind each refusal, and the
bytes in the bucket hashing to the digest in the row.

Pass the deployed URL instead of the localhost one to run the same checks
against production.

The one thing this cannot cover locally is the platform's own JWT gate. The
function verifies the token itself with `auth.getUser()`, so the check is real
either way, but the gateway rejecting an unauthenticated request before the
function runs is only observable once deployed.

**This pair is what found the bug that migration 0009 fixes.** Everything passed
in memory and in the SQL suite; the proposal write failed the first time it met
a real PostgREST connection, because each request is its own transaction and the
deferred grounding check fired before any citation existed. Run these against
the live project after any change to the pipeline or the adapters.

## 9. Seeded data cannot be deleted

`--clean` on the seed script removes what it can and tells you what it could
not. Once a seeded case has a contract, it stays: evidence, proposals, dispute
events and the audit log are append-only, and contracts hold their parties with
ON DELETE RESTRICT, so neither the profile nor the auth user behind it can be
removed. Each run uses its own tag so they never collide.

That is correct for a trust product, and it is also a question to put to the
lawyer alongside the escrow work: a right-to-erasure request under UAE data
protection law meets a schema that is deliberately unable to erase. The answer
is probably redaction rather than deletion, but it needs deciding before launch
rather than after the first request arrives.

## 10. What is not wired up yet

- Deployment. Both functions are written and verified; neither is deployed.
- Text extraction from uploaded evidence. `extractedText` is null everywhere,
  so the model sees filenames and notes rather than contents.
- Anything that calls `resolve-dispute` automatically. Today it is a POST
  someone has to make.
- A real model call. The pipeline has never run against Anthropic; that needs
  `ANTHROPIC_API_KEY` set as a function secret, and it costs money per dispute.
