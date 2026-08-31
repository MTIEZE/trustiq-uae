-- ---------------------------------------------------------------------------
-- The control centre.
--
-- 0020 built an operator panel that returns counts and never a name. That was
-- the right first move and it is not enough to run a platform: somebody writes
-- in, and the answer is in a row you cannot see.
--
-- So this adds the parts that do return personal data. The rule 0020 held is
-- not abandoned, it is paid for:
--
--   every read of a person's record writes a row saying who looked, at whom,
--   and why they were allowed to;
--   the log is append-only, and an operator cannot read it, so the audit is
--   not something the audited can tidy;
--   the aggregate functions from 0020 are untouched and still name nobody, so
--   the dashboard somebody leaves open on a laptop is still only numbers.
--
-- Being able to see a person's file is a real power. Making it leave a trace is
-- the difference between an operator and a spectator, and it is the only reason
-- this migration is defensible at all.
-- ---------------------------------------------------------------------------

create table if not exists app.admin_access_log (
  id        bigint generated always as identity primary key,
  actor_id  uuid not null references public.profiles (id) on delete restrict,

  -- 'people' for a search, 'person' for one file, 'queue', 'disputes'.
  what      text not null check (length(btrim(what)) between 1 and 40),

  -- Who was looked at, when it was one person. Null for a listing.
  subject_id uuid references public.profiles (id) on delete set null,

  -- What was typed, when it was a search. Bounded and never rendered.
  query     text check (length(query) <= 200),

  looked_at timestamptz not null default now()
);

comment on table app.admin_access_log is
  'Every operator read of somebody personal data. Append-only, and unreadable by operators.';

create index if not exists admin_access_log_actor_idx
  on app.admin_access_log (actor_id, looked_at desc);
create index if not exists admin_access_log_subject_idx
  on app.admin_access_log (subject_id, looked_at desc);

drop trigger if exists admin_access_log_immutable on app.admin_access_log;
create trigger admin_access_log_immutable
  before update or delete on app.admin_access_log
  for each row execute function app.forbid_mutation();

/* Asserts the caller is an operator and records that they looked. */
create or replace function app.note_admin_access(
  p_what    text,
  p_subject uuid default null,
  p_query   text default null
)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  perform app.assert_admin(p_what);
  insert into app.admin_access_log (actor_id, what, subject_id, query)
  values (auth.uid(), p_what, p_subject, nullif(btrim(coalesce(p_query, '')), ''));
end;
$$;

-- ---------------------------------------------------------------------------
-- People
--
-- A search rather than a browse. `admin_people` with no term returns the most
-- recent twenty, which is the working list; anything beyond that needs a term.
-- Not a security boundary, since an operator could page through it either way,
-- but the shape of the tool decides what somebody does with it by default, and
-- the default here should be answering a question rather than reading the list.
-- ---------------------------------------------------------------------------

create or replace function public.admin_people(
  p_query text default null,
  p_limit integer default 20
)
returns table (
  user_id      uuid,
  full_name    text,
  email        text,
  verified_at  timestamptz,
  provider     text,
  joined       timestamptz,
  last_seen    date,
  contracts    integer,
  suspended    boolean
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_term text := nullif(btrim(coalesce(p_query, '')), '');
begin
  perform app.note_admin_access('people', null, v_term);

  return query
  select p.id, p.full_name, p.email, p.identity_verified_at, p.identity_provider,
         p.created_at,
         (select max(a.day) from app.activity a where a.user_id = p.id),
         (select count(*)::integer from public.transactions t
           where p.id in (t.buyer_id, t.seller_id)),
         coalesce((select u.banned_until > now() from auth.users u where u.id = p.id), false)
  from app.real_profiles p
  where v_term is null
     or p.full_name ilike '%' || v_term || '%'
     or p.email ilike '%' || v_term || '%'
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

create or replace function public.admin_person(p_user_id uuid)
returns table (
  full_name    text,
  email        text,
  verified_at  timestamptz,
  provider     text,
  joined       timestamptz,
  last_seen    date,
  suspended    boolean,
  verification text,
  contracts    integer,
  disputes     integer,
  evidence     integer
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.note_admin_access('person', p_user_id, null);

  return query
  select p.full_name, p.email, p.identity_verified_at, p.identity_provider,
         p.created_at,
         (select max(a.day) from app.activity a where a.user_id = p.id),
         coalesce((select u.banned_until > now() from auth.users u where u.id = p.id), false),
         (select r.state from app.verification_requests r
           where r.user_id = p.id order by r.submitted_at desc limit 1),
         (select count(*)::integer from public.transactions t
           where p.id in (t.buyer_id, t.seller_id)),
         (select count(*)::integer from public.disputes d
           join public.transactions t on t.id = d.transaction_id
           where p.id in (t.buyer_id, t.seller_id)),
         (select count(*)::integer from public.evidence e where e.uploaded_by = p.id)
  from public.profiles p
  where p.id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shutting an account
--
-- Two things it refuses, both learned from other people's incidents: an
-- operator cannot suspend themselves, and cannot suspend another operator. The
-- first is an accident waiting to happen and the second is how one bad day
-- becomes nobody being able to fix it.
--
-- Suspension is a lock on signing in. Nothing is deleted and no contract
-- changes, because the other party's record is not the suspended person's to
-- take away.
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

  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- The queue, and the cases
-- ---------------------------------------------------------------------------

create or replace function public.admin_verification_queue()
returns table (
  request_id    uuid,
  user_id       uuid,
  full_name     text,
  email         text,
  legal_name    text,
  document_kind text,
  how           text,
  waiting_since timestamptz,
  name_differs  boolean
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
         lower(btrim(r.legal_name)) is distinct from lower(btrim(p.full_name))
  from app.verification_requests r
  join public.profiles p on p.id = r.user_id
  where r.state = 'pending'
  order by r.submitted_at;
end;
$$;

create or replace function public.admin_disputes()
returns table (
  dispute_id     uuid,
  transaction_id uuid,
  state          text,
  opened_at      timestamptz,
  amount_fils    bigint,
  buyer_name     text,
  seller_name    text,
  has_proposal   boolean,
  accepted_by    integer,
  runs           integer
)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.note_admin_access('disputes', null, null);

  return query
  select d.id, t.id, d.state::text, d.opened_at, d.disputed_amount_fils::bigint,
         b.full_name, s.full_name,
         exists (select 1 from public.resolution_proposals r where r.dispute_id = d.id),
         (select count(*)::integer from public.dispute_acceptances a
           join public.resolution_proposals r on r.id = a.proposal_id
           where r.dispute_id = d.id),
         (select count(*)::integer from public.ai_call_log l where l.dispute_id = d.id)
  from public.disputes d
  join app.real_transactions t on t.id = d.transaction_id
  join public.profiles b on b.id = t.buyer_id
  join public.profiles s on s.id = t.seller_id
  order by
    case when d.state in ('escalated', 'human_review') then 0
         when d.state in ('open', 'ai_review', 'proposal_issued') then 1
         else 2 end,
    d.opened_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- What has been happening
--
-- Built from the logs that exist. There is no record of a failed sign-in
-- anywhere in this schema, so this does not pretend to be a security feed: it
-- is what people did, which is a different and more useful thing.
-- ---------------------------------------------------------------------------

create or replace function public.admin_activity(p_limit integer default 40)
returns table (
  at       timestamptz,
  kind     text,
  detail   text,
  actor    text
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  -- No personal names, so this one is an aggregate read and not logged as an
  -- access. Contract references, not people.
  perform app.assert_admin('the activity feed');

  return query
  select * from (
    select e.occurred_at, 'contract'::text, e.event::text, e.actor::text
    from public.transaction_events e
    join app.real_transactions t on t.id = e.transaction_id
    union all
    select e.occurred_at, 'dispute'::text, e.event::text, e.actor::text
    from public.dispute_events e
    join public.disputes d on d.id = e.dispute_id
    join app.real_transactions t on t.id = d.transaction_id
    union all
    select l.created_at, 'model'::text, l.validation_outcome, 'system'::text
    from public.ai_call_log l
    union all
    select c.checked_at, 'identity'::text, c.outcome, 'system'::text
    from app.identity_checks c
  ) as feed(at, kind, detail, actor)
  order by feed.at desc
  limit least(greatest(coalesce(p_limit, 40), 1), 200);
end;
$$;

-- ---------------------------------------------------------------------------
-- Who looked at whom
--
-- Not readable by an operator, on purpose. An audit trail the audited can read
-- is a list of what to avoid next time; one they can edit is nothing at all.
-- This is for the service role, which means a person at a terminal.
-- ---------------------------------------------------------------------------

create or replace function public.admin_access_history(p_days integer default 30)
returns table (
  looked_at  timestamptz,
  actor      text,
  what       text,
  subject    text,
  query      text
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('reading the access log');

  return query
  select l.looked_at, a.email, l.what, s.email, l.query
  from app.admin_access_log l
  join public.profiles a on a.id = l.actor_id
  left join public.profiles s on s.id = l.subject_id
  where l.looked_at > now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 365))
  order by l.looked_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on function public.admin_people(text, integer) from public, anon;
revoke all on function public.admin_person(uuid) from public, anon;
revoke all on function public.admin_set_suspended(uuid, boolean, text) from public, anon;
revoke all on function public.admin_verification_queue() from public, anon;
revoke all on function public.admin_disputes() from public, anon;
revoke all on function public.admin_activity(integer) from public, anon;
revoke all on function public.admin_access_history(integer) from public, anon, authenticated;

grant execute on function public.admin_people(text, integer) to authenticated;
grant execute on function public.admin_person(uuid) to authenticated;
grant execute on function public.admin_set_suspended(uuid, boolean, text) to authenticated;
grant execute on function public.admin_verification_queue() to authenticated;
grant execute on function public.admin_disputes() to authenticated;
grant execute on function public.admin_activity(integer) to authenticated;
grant execute on function public.admin_access_history(integer) to service_role;
