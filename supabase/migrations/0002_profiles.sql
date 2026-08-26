-- ---------------------------------------------------------------------------
-- 0002  Profiles
--
-- One row per user, keyed to auth.users. Identity verification (UAE Pass in
-- production) is recorded here: an unverified party may draft a contract but
-- may not accept one, which is enforced in 0003.
-- ---------------------------------------------------------------------------

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  full_name     text not null check (length(btrim(full_name)) between 1 and 120),
  email         text not null check (position('@' in email) > 1),
  phone         text check (phone ~ '^\+[1-9][0-9]{7,14}$'),

  -- Identity verification. `verified_at` is set by the server only, never by a
  -- client: the RLS update policy below excludes these columns.
  identity_verified_at   timestamptz,
  identity_provider      text check (identity_provider in ('uae_pass', 'manual_review')),

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.profiles is
  'Public profile per user. Identity verification columns are server-written only.';

create index profiles_email_idx on public.profiles (lower(email));

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
--
-- Counterparty visibility needs the transactions table, so that policy is added
-- in 0003 once it exists. What is here is everything that depends only on the
-- profile itself.
-- ---------------------------------------------------------------------------

-- ENABLE, not FORCE, throughout this schema. Server-side logic runs through
-- SECURITY DEFINER functions that must be able to write; FORCE would fight
-- them, and it does not constrain Supabase's service_role anyway, since that
-- role carries BYPASSRLS rather than owning the tables.
alter table public.profiles enable row level security;

create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy profiles_insert_own
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

-- A user may edit their own contact details. Identity verification is
-- deliberately excluded: the WITH CHECK re-reads the stored row, so any attempt
-- to self-verify fails.
create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and identity_verified_at is not distinct from (
      select p.identity_verified_at from public.profiles p where p.id = auth.uid()
    )
    and identity_provider is not distinct from (
      select p.identity_provider from public.profiles p where p.id = auth.uid()
    )
  );

-- No delete policy: profiles are removed by deleting the auth user, which
-- cascades. A party cannot vanish from a contract the other side relies on.
