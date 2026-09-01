-- ---------------------------------------------------------------------------
-- Somebody whose account is suspended is told, and told why.
--
-- Until now `admin_set_suspended` set banned_until, wrote the reason to the
-- access log, and stopped. The person found out because signing in stopped
-- working, with no reason and nothing to reply to. Writing the terms of use is
-- what surfaced it: the page had to either claim they are told, which was
-- false, or say plainly that they are not.
--
-- It cannot go through app.notifications. That table is contract-shaped — a
-- notification must name a transaction or a dispute, the sender groups them by
-- contract, and the email says "you have three things waiting". None of that
-- describes an account being closed to somebody. And the in-app channel is
-- useless here by definition: they cannot sign in to read it.
--
-- So: a small queue of its own, email only, with the operator's own words in
-- it. Which means those words are now read by the person they are about, and
-- the console asks for them differently.
-- ---------------------------------------------------------------------------

create table app.account_notices (
  id           bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,

  kind         text not null check (kind in ('suspended', 'reinstated')),

  -- What the operator wrote. Read by the person, word for word, which is the
  -- reason the console prompt changed with this migration.
  reason       text not null check (length(btrim(reason)) between 10 and 2000),

  created_at   timestamptz not null default now(),

  -- Per channel, so a failed send does not erase the fact that it happened.
  emailed_at   timestamptz,
  email_error  text
);

comment on table app.account_notices is
  'Told to somebody about their own account rather than about a contract. Email only: a suspended person cannot sign in to read anything.';

create index account_notices_pending_idx
  on app.account_notices (created_at)
  where emailed_at is null and email_error is null;

alter table app.account_notices enable row level security;

/**
 * The notice itself is fixed; only its delivery moves.
 *
 * Same shape as the reports table next door. A record of what somebody was
 * told, that could be edited into something else afterwards, is not a record.
 */
create or replace function app.notice_text_is_fixed()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'an account notice cannot be deleted'
      using errcode = 'check_violation';
  end if;

  if new.recipient_id is distinct from old.recipient_id
     or new.kind      is distinct from old.kind
     or new.reason    is distinct from old.reason
     or new.created_at is distinct from old.created_at
  then
    raise exception 'what somebody was told cannot be edited afterwards'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger account_notices_text_fixed
  before update or delete on app.account_notices
  for each row execute function app.notice_text_is_fixed();

-- ---------------------------------------------------------------------------
-- Suspension, now with the person on the other end of it.
-- ---------------------------------------------------------------------------

create or replace function public.admin_set_suspended(
  p_user_id   uuid,
  p_suspended boolean,
  p_reason    text
)
returns boolean
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  if length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception 'say why, in at least ten characters'
      using errcode = 'check_violation';
  end if;

  perform app.note_admin_access(
    case when p_suspended then 'suspend' else 'restore' end, p_user_id, p_reason);

  if p_user_id = auth.uid() then
    raise exception 'you cannot suspend yourself' using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.admins a where a.user_id = p_user_id) then
    raise exception 'an operator cannot be suspended from here'
      using errcode = 'insufficient_privilege';
  end if;

  update auth.users
  set banned_until = case when p_suspended then 'infinity'::timestamptz else null end
  where id = p_user_id;

  if not found then
    return false;
  end if;

  -- After the change, not before: a notice about a suspension that did not
  -- happen is worse than no notice.
  insert into app.account_notices (recipient_id, kind, reason)
  values (
    p_user_id,
    case when p_suspended then 'suspended' else 'reinstated' end,
    btrim(p_reason)
  );

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

create or replace function public.account_notices_to_send()
returns table (
  id           bigint,
  recipient_id uuid,
  email        text,
  full_name    text,
  locale       text,
  kind         text,
  reason       text
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select
    n.id, n.recipient_id, p.email, p.full_name,
    coalesce(p.preferred_locale, 'en'), n.kind, n.reason
  from app.account_notices n
  join public.profiles p on p.id = n.recipient_id
  where n.emailed_at is null
    and n.email_error is null
    -- No grace period, unlike the contract mail. That one waits in case the
    -- person is in the app and deals with it; this one is for somebody who has
    -- just been locked out and is looking at a sign-in screen that stopped
    -- working.
    --
    -- RFC 2606 reserves these and they can never be delivered. Every seeded
    -- account uses one, and each would bounce against the reputation the real
    -- mail depends on.
    and p.email !~* '@([a-z0-9-]+\.)*(test|invalid|example|localhost)$'
  order by n.created_at
  limit 100;
$$;

comment on function public.account_notices_to_send is
  'Account notices waiting to go out. One row per notice, not per person: being suspended and reinstated are two different things to say.';

create or replace function public.mark_account_notices_sent(
  p_ids   bigint[],
  p_error text default null
)
returns integer
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_rows integer;
begin
  update app.account_notices
  set emailed_at  = case when p_error is null then now() else null end,
      email_error = p_error
  where id = any (p_ids);

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- From `public` as well as from `anon`: Supabase grants EXECUTE to PUBLIC on
-- every new function here, and a revoke aimed at anon leaves a right held
-- through PUBLIC in place.
-- ---------------------------------------------------------------------------

revoke all on function public.account_notices_to_send()               from public, anon, authenticated;
revoke all on function public.mark_account_notices_sent(bigint[], text) from public, anon, authenticated;
revoke all on function app.notice_text_is_fixed()                     from public, anon, authenticated;

grant execute on function public.account_notices_to_send()               to service_role;
grant execute on function public.mark_account_notices_sent(bigint[], text) to service_role;
