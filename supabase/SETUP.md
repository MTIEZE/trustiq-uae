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

`npm run test:db` runs the full suite of 56 assertions against a throwaway
Postgres, so a failure there means the migrations are wrong rather than the
project being misconfigured.

## 5. Keys

From **Project Settings > API**. Two keys, and they are not interchangeable.

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

## 7. What is not wired up yet

The adapters in `packages/server/src/supabase` implement the ports, and their
row mapping is tested. What does not exist yet:

- An HTTP layer calling them. There is no endpoint to hit.
- Text extraction from uploaded evidence. `extractedText` is null everywhere,
  so the model currently sees filenames and notes rather than contents.
- Anything that runs the resolution pipeline on a schedule or a trigger.

Until those exist, the adapters compile and their mapping is verified, but no
code path has run against a real project.
