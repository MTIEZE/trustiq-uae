-- ---------------------------------------------------------------------------
-- An operator can decide a verification, which until now they could not.
--
-- What was wrong, exactly. 0021 built verification review as a service-role
-- action driven by a script on a machine: `verification_queue()` and
-- `decide_verification()` are revoked from `authenticated`, `decide` calls
-- `app.assert_system_caller`, and the writer it delegates to,
-- `record_manual_verification`, refuses outright when `auth.uid()` is not null.
-- Three separate refusals, all deliberate, all correct for a script.
--
-- Then 0026 added the Control Centre: `admin_verification_queue()` for an
-- operator to see the queue, and two buttons wired to `decide_verification`,
-- which nobody had opened to an operator. So the queue listed and the button
-- was refused with "permission denied for function decide_verification", every
-- time, since the day it shipped. The script path kept working, which is why
-- it went unnoticed: every test of verification acted as the service role, and
-- that is not who presses the button.
--
-- Reproduced before this was written, with scripts/verify-verification-console.mjs,
-- which signs in as an operator through the same publishable key the app ships
-- with and drives the whole path.
--
-- Nothing was half-done by the failure: the profile stayed unverified and the
-- request stayed pending. There is no split between what the console shows and
-- what the database holds, because the console could never write.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- One writer, reachable by both callers.
--
-- The identity_checks row and the profile stamp were inside
-- record_manual_verification, behind a guard that refuses a session. Lifted
-- into `app` so the operator path writes exactly the same two rows rather than
-- a second copy of them that drifts.
-- ---------------------------------------------------------------------------

create or replace function app.record_verification(
  p_user_id uuid,
  p_note    text
)
returns timestamptz
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_at timestamptz := now();
begin
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

-- The guard is assert_system_caller, and it has to stay that.
--
-- This body was first rewritten from the version in 0013, which asks only
-- whether auth.uid() is null. That silently undid the hardening 0014 exists
-- for: an `anon` caller has no auth.uid(), so the publishable key that ships
-- inside every copy of the app would have been able to verify any account.
-- The schema suite refused it by name, which is what that assertion is for.
--
-- Read the last definition of a function, not the first.
create or replace function public.record_manual_verification(
  p_user_id uuid,
  p_note    text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('verification');
  return app.record_verification(p_user_id, p_note);
end;
$$;

-- ---------------------------------------------------------------------------
-- A fourth answer: ask for more.
--
-- Refusing somebody who simply did not say enough is the wrong answer, and it
-- is the only one the queue had. `needs_more_info` leaves the request open and
-- hands it back to the person with a reason attached.
-- ---------------------------------------------------------------------------

alter table app.verification_requests drop constraint if exists verification_requests_state_check;
alter table app.verification_requests
  add constraint verification_requests_state_check
  check (state in ('pending', 'needs_more_info', 'approved', 'rejected', 'withdrawn'));

-- And the rule about what a decided row carries has to learn the same state.
-- `needs_more_info` is open, not decided: it has a reason and no decided_at,
-- which the original constraint allowed for no state at all.
alter table app.verification_requests drop constraint if exists decided_rows_carry_a_decision;
alter table app.verification_requests
  add constraint decided_rows_carry_a_decision check (
    (state = 'pending' and decided_at is null and decided_by is null)
    or (state = 'needs_more_info' and decided_at is null and decided_by is null)
    or (state = 'withdrawn' and decided_by is null)
    or (state in ('approved', 'rejected') and decided_at is not null)
  );

-- A person may answer a request for more, which the "one open request" rule
-- otherwise treats as a duplicate.
create or replace function public.request_verification(
  p_legal_name    text,
  p_document_kind text,
  p_how           text default null
)
returns table (
  request_id   uuid,
  state        text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me   uuid := auth.uid();
  v_id   uuid;
  v_open uuid;
begin
  if v_me is null then
    raise exception 'asking to be verified needs a signed-in caller'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_me) then
    raise exception 'finish setting up your account first'
      using errcode = 'no_data_found';
  end if;

  if exists (select 1 from public.profiles p
             where p.id = v_me and p.identity_verified_at is not null) then
    raise exception 'you are already verified' using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.verification_requests r
             where r.user_id = v_me and r.state = 'pending') then
    raise exception 'you already have a request waiting' using errcode = 'unique_violation';
  end if;

  -- Answering a request for more is an update, not a second request. Sending
  -- it back to `pending` is what puts it in front of an operator again, and
  -- the old reason goes: it was answered.
  select r.id into v_open
  from app.verification_requests r
  where r.user_id = v_me and r.state = 'needs_more_info'
  limit 1;

  if v_open is not null then
    update app.verification_requests
    set legal_name    = btrim(p_legal_name),
        document_kind = p_document_kind,
        how           = nullif(btrim(coalesce(p_how, '')), ''),
        state         = 'pending',
        submitted_at  = now(),
        reason        = null
    where id = v_open;
    v_id := v_open;
  else
    insert into app.verification_requests (user_id, legal_name, document_kind, how)
    values (v_me, btrim(p_legal_name), p_document_kind, nullif(btrim(coalesce(p_how, '')), ''))
    returning app.verification_requests.id into v_id;
  end if;

  return query
  select r.id, r.state, r.submitted_at
  from app.verification_requests r where r.id = v_id;
end;
$$;

comment on function public.request_verification is
  'Joins the verification queue, or answers a request for more information. One open request per person.';

-- The queue an operator reads has to show the ones handed back too, otherwise
-- a request sitting in needs_more_info is invisible to everybody.
--
-- Dropped and recreated: the row gains a column, and `create or replace`
-- cannot change a function's return type.
drop function if exists public.admin_verification_queue();

create function public.admin_verification_queue()
returns table (
  request_id    uuid,
  user_id       uuid,
  full_name     text,
  email         text,
  legal_name    text,
  document_kind text,
  how           text,
  waiting_since timestamptz,
  name_differs  boolean,
  state         text
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.note_admin_access('queue', null, null);

  return query
  select r.id, r.user_id, p.full_name, p.email,
         r.legal_name, r.document_kind, r.how, r.submitted_at,
         lower(btrim(r.legal_name)) is distinct from lower(btrim(p.full_name)),
         r.state
  from app.verification_requests r
  join public.profiles p on p.id = r.user_id
  where r.state in ('pending', 'needs_more_info')
  order by r.state desc, r.submitted_at;
end;
$$;

-- And the badge counts the same set, so the number and the list agree.
create or replace function public.admin_verification_pending()
returns bigint
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_count bigint;
begin
  perform app.assert_admin('the verification queue length');

  select count(*) into v_count
  from app.verification_requests r
  join app.real_profiles p on p.id = r.user_id
  where r.state = 'pending';

  return v_count;
end;
$$;

-- The person's own view has to know the state too.
--
-- It did not, and the case mapped every unrecognised state to 'none'. So a
-- request an operator had handed back showed the person "you have never asked"
-- while the queue waited on their answer: the console and the app describing
-- the same row differently, which is the one failure mode this whole area is
-- supposed to make impossible. Caught by driving the path rather than by
-- reading it.
create or replace function public.my_verification()
returns table (
  standing      text,
  since         timestamptz,
  reason        text,
  document_kind text,
  legal_name    text
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'reading your verification needs a signed-in caller'
      using errcode = 'insufficient_privilege';
  end if;

  -- Verified wins over anything in the queue. Somebody verified through UAE
  -- Pass while a manual request sat waiting is verified, and being shown
  -- "pending" would be false.
  if exists (select 1 from public.profiles p
             where p.id = v_me and p.identity_verified_at is not null) then
    return query
    select 'verified'::text, p.identity_verified_at, null::text,
           p.identity_provider, p.full_name
    from public.profiles p where p.id = v_me;
    return;
  end if;

  return query
  select
    case r.state when 'pending' then 'pending'
                 when 'needs_more_info' then 'needs_more_info'
                 when 'rejected' then 'rejected'
                 else 'none' end,
    coalesce(r.decided_at, r.submitted_at),
    r.reason,
    r.document_kind,
    r.legal_name
  from app.verification_requests r
  where r.user_id = v_me
  order by r.submitted_at desc
  limit 1;

  if not found then
    return query select 'none'::text, null::timestamptz, null::text, null::text, null::text;
  end if;
end;
$$;

comment on function public.my_verification is
  'Where the caller stands: none, pending, needs_more_info with the question, rejected with a reason, or verified.';

-- ---------------------------------------------------------------------------
-- The decision, made by an operator
-- ---------------------------------------------------------------------------

create or replace function public.admin_decide_verification(
  p_request_id uuid,
  p_outcome    text,
  p_note       text
)
returns text
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_request app.verification_requests%rowtype;
begin
  perform app.assert_admin('deciding a verification');

  if p_outcome not in ('approved', 'rejected', 'needs_more_info') then
    raise exception 'an outcome is approved, rejected or needs_more_info'
      using errcode = 'check_violation';
  end if;

  -- Required on every outcome, including approval. Why somebody was verified
  -- is the record, and "ok" is not one.
  if length(btrim(coalesce(p_note, ''))) < 10 then
    raise exception 'say why, in at least ten characters'
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.verification_requests where id = p_request_id;
  if v_request.id is null then
    raise exception 'no such request' using errcode = 'no_data_found';
  end if;
  if v_request.state not in ('pending', 'needs_more_info') then
    raise exception 'that request was already %', v_request.state
      using errcode = 'check_violation';
  end if;

  -- Logged before the write, like every other operator action: looking at
  -- somebody's file leaves a trace whether or not the write then succeeds.
  perform app.note_admin_access('verification', v_request.user_id, p_note);

  if p_outcome = 'approved' then
    perform app.record_verification(v_request.user_id, p_note);
    update app.verification_requests
    set state = 'approved', decided_at = now(), reason = null
    where id = p_request_id;
  elsif p_outcome = 'rejected' then
    update app.verification_requests
    set state = 'rejected', decided_at = now(), reason = btrim(p_note)
    where id = p_request_id;
  else
    -- Handed back, not closed. decided_at stays null: nothing was decided.
    update app.verification_requests
    set state = 'needs_more_info', reason = btrim(p_note)
    where id = p_request_id;
  end if;

  -- And the person hears. Before 0030 there was no channel for this at all.
  insert into app.account_notices (recipient_id, kind, reason)
  values (
    v_request.user_id,
    case p_outcome
      when 'approved' then 'verification_approved'
      when 'rejected' then 'verification_rejected'
      else 'verification_more_info'
    end,
    btrim(p_note)
  );

  return p_outcome;
end;
$$;

comment on function public.admin_decide_verification is
  'Approve, refuse, or ask for more, as an operator through their own session. The service-role path decide_verification stays for the scripts.';

-- The notice queue learns three more things to say.
alter table app.account_notices drop constraint if exists account_notices_kind_check;
alter table app.account_notices
  add constraint account_notices_kind_check
  check (kind in (
    'suspended', 'reinstated',
    'verification_approved', 'verification_rejected', 'verification_more_info'
  ));

-- ---------------------------------------------------------------------------
-- Grants
--
-- From `public` first. Supabase grants EXECUTE to PUBLIC on every new function
-- in this schema, and revoking from anon leaves a right held through PUBLIC.
-- ---------------------------------------------------------------------------

revoke all on function public.admin_verification_queue() from public, anon;
revoke all on function public.admin_decide_verification(uuid, text, text) from public, anon;
revoke all on function app.record_verification(uuid, text) from public, anon, authenticated;

grant execute on function public.admin_verification_queue()                to authenticated;
grant execute on function public.admin_decide_verification(uuid, text, text) to authenticated;
