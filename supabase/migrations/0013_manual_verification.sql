-- ---------------------------------------------------------------------------
-- 0013  Verifying somebody by hand
--
-- The identity gate refuses to activate a contract until both parties are
-- verified. Nothing could verify anybody. UAE Pass needs TrustIQ registered as
-- a Service Provider, which is a paperwork step, and the profiles policy
-- deliberately refuses to let a user set their own verification. The result:
-- a real person could sign up, draft a contract, send it, and then neither
-- side could ever accept it. Everything built after acceptance was unreachable
-- to anyone who was not seeded with the service role.
--
-- This is the bridge. Someone at TrustIQ looks at an Emirates ID and records
-- what they saw. It is worth less than UAE Pass and it says so: the profile is
-- stamped `manual_review`, not `uae_pass`, so nobody reading the row later can
-- mistake one for the other.
--
-- Two things make it a bridge rather than a hole.
--
-- **Every check is recorded, and the record cannot be edited.** Marking someone
-- verified is the claim the whole product rests on. If it turns out to be
-- wrong, the question is who made it, when, and on the basis of what, and that
-- has to have an answer.
--
-- **A note is required.** Not a checkbox. Whoever verifies has to write down
-- what they actually looked at, because "I checked" is not a record of
-- anything.
-- ---------------------------------------------------------------------------

create table app.identity_checks (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete restrict,

  -- 'verified' or 'revoked'. Both are recorded: a verification that was
  -- withdrawn is more interesting than one that was never made.
  outcome    text not null check (outcome in ('verified', 'revoked')),

  -- What was looked at, in the words of whoever looked. Required, and long
  -- enough that it cannot be a single character standing in for a tick.
  note       text not null check (length(btrim(note)) between 10 and 2000),

  checked_at timestamptz not null default now()
);

comment on table app.identity_checks is
  'Append-only record of every manual identity decision. Service role only: no client can read it or write to it.';

create index identity_checks_user_idx on app.identity_checks (user_id, checked_at desc);

create trigger identity_checks_immutable
  before update or delete on app.identity_checks
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Recording a check
--
-- No client grant on either function. Verifying somebody is an administrative
-- act performed with the service role, and the friction is the point: it
-- should not be possible from a phone.
-- ---------------------------------------------------------------------------

create or replace function public.record_manual_verification(
  p_user_id uuid,
  p_note    text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_at timestamptz := now();
begin
  if auth.uid() is not null then
    raise exception 'verification is an administrative action and cannot be performed from a user session'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'no profile for %', p_user_id using errcode = 'no_data_found';
  end if;

  -- The record first. If the profile update fails, there is still a note
  -- saying somebody tried, which is the more useful half of the pair.
  insert into app.identity_checks (user_id, outcome, note)
  values (p_user_id, 'verified', p_note);

  update public.profiles
  set identity_verified_at = v_at,
      -- Stamped for what it is. A row that says `uae_pass` when a person read
      -- a photograph of an ID card would be a lie told to every later reader.
      identity_provider    = 'manual_review'
  where id = p_user_id;

  return v_at;
end;
$$;

comment on function public.record_manual_verification is
  'Marks a profile verified after a person checked their documents. Stamped manual_review, never uae_pass. Service role only.';

create or replace function public.revoke_verification(
  p_user_id uuid,
  p_note    text
)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  if auth.uid() is not null then
    raise exception 'verification is an administrative action and cannot be performed from a user session'
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.identity_checks (user_id, outcome, note)
  values (p_user_id, 'revoked', p_note);

  update public.profiles
  set identity_verified_at = null,
      identity_provider    = null
  where id = p_user_id;

  -- Contracts already accepted are left alone, deliberately. They were
  -- accepted between two parties who were verified at the time, and that is
  -- what the timeline records. Reaching back to undo them would rewrite a
  -- history this schema exists to keep.
end;
$$;

comment on function public.revoke_verification is
  'Withdraws a verification. Contracts already accepted are untouched: they were valid when they were accepted, and the record says so.';

revoke all on function public.record_manual_verification(uuid, text) from public;
revoke all on function public.revoke_verification(uuid, text) from public;
grant execute on function public.record_manual_verification(uuid, text) to service_role;
grant execute on function public.revoke_verification(uuid, text) to service_role;
