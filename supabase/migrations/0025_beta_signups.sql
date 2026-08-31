-- ---------------------------------------------------------------------------
-- People asking to be told when the app opens.
--
-- The site is being rebuilt around a download button, and there is nothing to
-- download: no App Store listing, no Play listing, and a submission that still
-- needs the data safety form, a content rating, screenshots and a closed test.
-- Pretending otherwise was ruled out, so the call to action is joining the
-- beta, and this is where that lands.
--
-- ---------------------------------------------------------------------------
-- An endpoint anybody can write to, said plainly
--
-- This is the first table in the project that `anon` may insert into, and that
-- is a real decision rather than an oversight. A signup form that needs an
-- account is not a signup form.
--
-- What it costs: somebody can fill it with rubbish. There is no rate limiting
-- in front of PostgREST, and pretending a CHECK constraint is one would be
-- theatre. What limits the damage instead:
--
--   nothing sensitive is in here, so a leak is a list of addresses that were
--   given to us on purpose;
--   nobody can read it back, not even the person who wrote the row, so it
--   cannot be used to find out who else signed up;
--   it can be truncated without losing anything the product depends on.
--
-- If it is ever abused, the answer is a turnstile in front of the form, not a
-- cleverer constraint here.
-- ---------------------------------------------------------------------------

create table if not exists public.beta_signups (
  id         bigint generated always as identity primary key,

  -- Trimmed before it is judged. A form field that a phone keyboard put a
  -- trailing space in holds a perfectly good address, and refusing it teaches
  -- somebody that the site is broken rather than that they made a typo.
  email      text not null
               check (length(btrim(email)) between 5 and 254)
               check (btrim(email) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),

  -- Which page it came from, so it is possible to tell later which part of the
  -- site actually convinced anybody. Bounded, and never rendered anywhere.
  source     text check (length(source) <= 60),

  -- Free text if the person wants to say who they are. Optional on purpose:
  -- every extra required field costs signups, and none of them is worth more
  -- than the address.
  note       text check (length(note) <= 500),

  created_at timestamptz not null default now()
);

comment on table public.beta_signups is
  'Addresses given to us on purpose, to be told when the app opens. Writable by anyone, readable by nobody but the service role.';

create index if not exists beta_signups_created_idx on public.beta_signups (created_at);

alter table public.beta_signups enable row level security;

-- Insert, and only insert. No select policy for any client role, so a form
-- that adds a row cannot also read the list back.
drop policy if exists beta_signups_anyone_may_join on public.beta_signups;
create policy beta_signups_anyone_may_join
  on public.beta_signups for insert
  to anon, authenticated
  with check (true);

-- Deliberately not append-only. A list of marketing contacts is the one thing
-- here somebody has a right to be removed from, and app.forbid_mutation would
-- make honouring that impossible.
revoke select, update, delete on public.beta_signups from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reading it
--
-- Deduplicated on the way out rather than on the way in. A unique index would
-- turn a second signup into an error, and an error that says "you are already
-- on the list" tells anybody with a form whether a given address is.
-- ---------------------------------------------------------------------------

create or replace function public.beta_list()
returns table (email text, first_seen timestamptz, times integer, sources text[])
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('reading the beta list');

  return query
  select lower(btrim(b.email)),
         min(b.created_at),
         count(*)::integer,
         array_agg(distinct b.source) filter (where b.source is not null)
  from public.beta_signups b
  group by lower(btrim(b.email))
  order by min(b.created_at);
end;
$$;

revoke all on function public.beta_list() from public, anon, authenticated;
grant execute on function public.beta_list() to service_role;

-- ---------------------------------------------------------------------------
-- And a count for the panel, which is allowed to know how many without
-- knowing who. Same rule as everything else in 0020.
-- ---------------------------------------------------------------------------

create or replace function public.admin_beta_waiting()
returns bigint
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_count bigint;
begin
  perform app.assert_admin('the beta list size');
  select count(distinct lower(btrim(email))) into v_count from public.beta_signups;
  return v_count;
end;
$$;

revoke all on function public.admin_beta_waiting() from public, anon;
grant execute on function public.admin_beta_waiting() to authenticated;
