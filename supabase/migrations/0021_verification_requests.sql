-- ---------------------------------------------------------------------------
-- Asking to be verified.
--
-- Verification was already enforced and already recorded. 0003 refuses to make
-- a contract binding unless both parties are verified, and 0013 writes an
-- append-only check with the reason somebody was. What was missing is the half
-- in between: a person had no way to ask, and no way to see where they stood.
--
-- In the app that showed up as a screen of explanation and an email address.
-- Somebody who signed up could not reach the end of a contract without writing
-- personally to Mohamed and waiting for a script to run, and nothing in the app
-- ever told them their request had been received, let alone refused.
--
-- Three states did not exist anywhere before this file: asked, refused, and
-- refused-with-a-reason-you-can-answer. A person was verified or they were not,
-- and "never asked" looked exactly like "asked yesterday".
--
-- ---------------------------------------------------------------------------
-- What this deliberately does not do
--
-- It does not take a document. `evidence.transaction_id` is not null, because a
-- document filed as evidence belongs to a contract, and an Emirates ID belongs
-- to a person; reusing that table would mean weakening the constraint that
-- makes evidence meaningful. Building a second private bucket for identity
-- documents is a real piece of work and a real data-protection liability, and
-- for a closed beta the proof still happens the way it happens today: in
-- person, over a call, or through UAE Pass once it is connected.
--
-- So the request carries what somebody claims and how they propose to show it.
-- The looking is still done by a human, and 0013 still records what they saw.
-- ---------------------------------------------------------------------------

create table if not exists app.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,

  -- 'withdrawn' is the person changing their mind. Kept apart from 'rejected'
  -- because one is their decision and the other is ours, and a queue that
  -- confuses the two would chase people who already left.
  state         text not null default 'pending'
                  check (state in ('pending', 'approved', 'rejected', 'withdrawn')),

  -- What they say their name is. Separate from profiles.full_name, which is
  -- whatever they typed at signup: the claim being checked has to be the claim
  -- they made, not one they can edit afterwards.
  legal_name    text not null check (length(btrim(legal_name)) between 2 and 120),

  document_kind text not null
                  check (document_kind in ('emirates_id', 'passport', 'trade_licence')),

  -- How they propose to show it. Free text on purpose: at this volume the
  -- useful answer is a sentence, not a dropdown.
  how           text check (length(btrim(how)) <= 1000),

  submitted_at  timestamptz not null default now(),

  decided_at    timestamptz,
  decided_by    uuid references public.profiles (id) on delete set null,

  -- Why, when the answer is no. Required for a refusal by the function below,
  -- because "rejected" with no reason is a dead end for the person and a
  -- support ticket for us.
  reason        text check (length(btrim(reason)) <= 1000),

  constraint decided_rows_carry_a_decision check (
    (state = 'pending'  and decided_at is null and decided_by is null)
    or (state = 'withdrawn' and decided_by is null)
    or (state in ('approved', 'rejected') and decided_at is not null)
  ),

  constraint a_refusal_says_why check (
    state <> 'rejected' or length(btrim(coalesce(reason, ''))) >= 10
  )
);

comment on table app.verification_requests is
  'Somebody asking to be verified, and what came of it. The looking is still done by a person; 0013 records what they saw.';

-- One open request each. Without this, somebody tapping the button twice joins
-- the queue twice, and the second one is answered after the first has already
-- verified them.
create unique index if not exists verification_requests_one_open
  on app.verification_requests (user_id)
  where state = 'pending';

create index if not exists verification_requests_queue_idx
  on app.verification_requests (submitted_at)
  where state = 'pending';

-- ---------------------------------------------------------------------------
-- Asking
-- ---------------------------------------------------------------------------

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
  v_me uuid := auth.uid();
  v_id uuid;
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

  insert into app.verification_requests (user_id, legal_name, document_kind, how)
  values (v_me, btrim(p_legal_name), p_document_kind, nullif(btrim(coalesce(p_how, '')), ''))
  returning app.verification_requests.id into v_id;

  return query
  select r.id, r.state, r.submitted_at
  from app.verification_requests r where r.id = v_id;
end;
$$;

comment on function public.request_verification is
  'Joins the verification queue. One open request per person.';

-- ---------------------------------------------------------------------------
-- Where do I stand
--
-- Always returns exactly one row, including for somebody who has never asked.
-- A screen that has to tell the difference between "no rows" and "no request"
-- gets it wrong eventually, and the wrong answer here is telling a verified
-- person they are not.
-- ---------------------------------------------------------------------------

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
  'Where the caller stands: none, pending, rejected with a reason, or verified.';

-- ---------------------------------------------------------------------------
-- Changing your mind
-- ---------------------------------------------------------------------------

create or replace function public.withdraw_verification_request()
returns boolean
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me   uuid := auth.uid();
  v_rows integer;
begin
  if v_me is null then
    raise exception 'withdrawing needs a signed-in caller'
      using errcode = 'insufficient_privilege';
  end if;

  update app.verification_requests
  set state = 'withdrawn', decided_at = now()
  where user_id = v_me and state = 'pending';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

-- ---------------------------------------------------------------------------
-- Deciding
--
-- Service role only, exactly like record_manual_verification, and for the same
-- reason: saying who somebody is cannot be an action available to anything that
-- ships to a device. It goes through scripts/verify-identity.mjs.
--
-- Approval routes through record_manual_verification rather than stamping the
-- profile here, so there stays one place where a profile becomes verified and
-- one append-only record of why.
-- ---------------------------------------------------------------------------

create or replace function public.decide_verification(
  p_request_id uuid,
  p_approve    boolean,
  p_note       text
)
returns table (
  outcome text,
  who     text
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_request app.verification_requests%rowtype;
begin
  perform app.assert_system_caller('deciding a verification');

  select * into v_request from app.verification_requests where id = p_request_id;
  if v_request.id is null then
    raise exception 'no such request' using errcode = 'no_data_found';
  end if;
  if v_request.state <> 'pending' then
    raise exception 'that request was already %', v_request.state
      using errcode = 'check_violation';
  end if;

  if p_approve then
    -- Raises if the note is too short, which is deliberate: the reason
    -- somebody was verified is the record, and it is required.
    perform public.record_manual_verification(v_request.user_id, p_note);

    update app.verification_requests
    set state = 'approved', decided_at = now(), reason = null
    where id = p_request_id;
  else
    if length(btrim(coalesce(p_note, ''))) < 10 then
      raise exception 'a refusal has to say why, in at least ten characters'
        using errcode = 'check_violation';
    end if;

    update app.verification_requests
    set state = 'rejected', decided_at = now(), reason = btrim(p_note)
    where id = p_request_id;
  end if;

  return query
  select case when p_approve then 'approved' else 'rejected' end::text,
         v_request.legal_name;
end;
$$;

comment on function public.decide_verification is
  'Answers one request. Approval goes through record_manual_verification so there is one path to a verified profile.';

-- ---------------------------------------------------------------------------
-- The queue
--
-- Service role only, and not in the operator panel. Everything in 0020 returns
-- counts and never a name; this returns names, because a queue you cannot act
-- on is not a queue. Keeping it on this side of the line means that rule stays
-- absolute rather than becoming a rule with an exception.
--
-- The panel gets the count instead, which is enough to know there is work.
-- ---------------------------------------------------------------------------

create or replace function public.verification_queue()
returns table (
  request_id    uuid,
  user_id       uuid,
  full_name     text,
  email         text,
  legal_name    text,
  document_kind text,
  how           text,
  waiting_since timestamptz
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('reading the verification queue');

  return query
  select r.id, r.user_id, p.full_name, p.email,
         r.legal_name, r.document_kind, r.how, r.submitted_at
  from app.verification_requests r
  join public.profiles p on p.id = r.user_id
  where r.state = 'pending'
  order by r.submitted_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- The panel learns there is work waiting
-- ---------------------------------------------------------------------------

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

  -- Filtered to real people, like everything else in the panel: the scripts
  -- create accounts at RFC 2606 domains and they are not customers waiting.
  select count(*) into v_count
  from app.verification_requests r
  join app.real_profiles p on p.id = r.user_id
  where r.state = 'pending';

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- The three a person calls about themselves go to `authenticated`. Deciding
-- and reading the queue go to nobody: they are reached with the service role,
-- through a script, on a machine. The sweep in schema.test.sql insists nothing
-- here is reachable with the key that ships inside the app.
-- ---------------------------------------------------------------------------

revoke all on function public.request_verification(text, text, text) from public, anon;
revoke all on function public.my_verification() from public, anon;
revoke all on function public.withdraw_verification_request() from public, anon;
revoke all on function public.decide_verification(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.verification_queue() from public, anon, authenticated;
revoke all on function public.admin_verification_pending() from public, anon;

grant execute on function public.request_verification(text, text, text) to authenticated;
grant execute on function public.my_verification() to authenticated;
grant execute on function public.withdraw_verification_request() to authenticated;
grant execute on function public.admin_verification_pending() to authenticated;

grant execute on function public.decide_verification(uuid, boolean, text) to service_role;
grant execute on function public.verification_queue() to service_role;
