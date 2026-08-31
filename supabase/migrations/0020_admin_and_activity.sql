-- ---------------------------------------------------------------------------
-- The operator's view.
--
-- Everything here answers questions about the platform rather than about a
-- person: how many signed up, how many came back, how far contracts get, and
-- whether the model's proposals are being accepted. That last one is not a
-- vanity metric. The whole product rests on "the AI proposes, the parties
-- decide", and if people refuse most of what it proposes then the thesis is
-- wrong and this is the number that says so.
--
-- Two rules shape the whole file.
--
-- Aggregates only. Every function here is `security definer` and reads past
-- RLS, which is the point: an operator has to see contracts they are not party
-- to. The safeguard is that nothing returns a name, an email, a claim or a
-- contract's terms. If `app.is_admin()` were ever wrong, what escapes is
-- counts. A panel that could also list people would turn one mistake into a
-- database dump, so it cannot list people. Support lookups will need their own
-- function, with its own access log, on the day there is a reason for one.
--
-- Re-runnable. There is no migration ledger in this project, applying is done
-- by naming a file, and the one thing worse than running this twice is being
-- afraid to. Six earlier migrations already do the same.
--
-- Days are Dubai days. Bucketing on UTC would cut the day at 4am local, and
-- "how many people used it on Tuesday" would quietly mean something else than
-- it says. The product is in the UAE, so the calendar is too.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Who is an operator
--
-- Deliberately not the reviewer list. A reviewer decides a case somebody
-- escalated; an operator watches the business. The same person may well be
-- both today, but they are different authorities and merging them would mean
-- adding somebody to the metrics panel also hands them live disputes.
--
-- Nothing in any client API writes to this table. It is filled from SQL or
-- with the service role, which is the same posture as app.reviewers: the list
-- of people who can see everything must not be reachable by anything that
-- ships inside an app.
-- ---------------------------------------------------------------------------

create table if not exists app.admins (
  user_id  uuid primary key references public.profiles (id) on delete restrict,
  added_at timestamptz not null default now(),
  note     text
);

comment on table app.admins is
  'Who may read the platform aggregates. Filled from SQL only, never from a client.';

create or replace function app.is_admin()
returns boolean
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select auth.uid() is not null
     and exists (select 1 from app.admins a where a.user_id = auth.uid());
$$;

-- Said once, so every function below reads the same way and a new one cannot
-- invent a slightly different refusal.
create or replace function app.assert_admin(p_what text)
returns void
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
begin
  if not app.is_admin() then
    raise exception 'reading % is an operator action' , p_what
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Who counts
--
-- Every number below is about real people, and the seed and verification
-- scripts have put a lot of accounts in this database that are not any. On the
-- day this was written the live project held 38 profiles of which 6 belonged to
-- somebody; a panel whose headline is wrong by a factor of six is worse than no
-- panel, because it is wrong quietly.
--
-- The rule is the one notifications_to_send already uses, and deliberately the
-- same one: RFC 2606 reserves these domains so nothing at them can ever be a
-- person. Reusing the predicate rather than inventing a second one means the
-- panel and the post office agree about who exists.
--
-- A view rather than a repeated `where`, because the same filter has to reach
-- contracts and disputes too. Counting 6 people but 17 contracts, when 11 of
-- those contracts are between accounts that do not exist, is the same lie told
-- in a different column.
-- ---------------------------------------------------------------------------

create or replace view app.real_profiles as
  select p.*
  from public.profiles p
  where p.email !~* '@([a-z0-9-]+\.)*(test|invalid|example|localhost)$';

comment on view app.real_profiles is
  'Profiles belonging to somebody. Excludes the RFC 2606 domains the scripts use.';

-- A contract is real when both sides are. One test account on either side and
-- the whole row is an artefact of a script.
create or replace view app.real_transactions as
  select t.*
  from public.transactions t
  where exists (select 1 from app.real_profiles r where r.id = t.buyer_id)
    and exists (select 1 from app.real_profiles r where r.id = t.seller_id);

comment on view app.real_transactions is
  'Contracts where both parties are real people.';

-- ---------------------------------------------------------------------------
-- Activity
--
-- One row per person per day they opened the app. Not an event stream: there
-- is no screen name, no duration, no sequence, nothing that says what somebody
-- looked at. It answers "did they come back" and refuses to answer anything
-- else, which is the most a trust product should know about its own users
-- without asking them.
--
-- This is also why there is no third-party analytics SDK anywhere in the app.
-- One bit per person per day, held in the same database as everything else,
-- under the same rules, is a smaller promise to keep than a tracker.
--
-- The foreign key cascades. Somebody who closes an account and is fully
-- deleted takes their attendance with them, which does move historical
-- numbers very slightly, and is the right trade: a deleted person is deleted.
-- It does not block that deletion either, and a test pins that, because
-- close_account only deletes outright when nothing is holding the profile and
-- a row saying "was here on Tuesday" must never be what holds somebody.
-- ---------------------------------------------------------------------------

create table if not exists app.activity (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day     date not null,
  primary key (user_id, day)
);

comment on table app.activity is
  'One row per person per Dubai day they opened the app. No event stream, by design.';

create index if not exists activity_day_idx on app.activity (day);

create or replace function public.record_activity()
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  -- Written so it can never be the reason a launch fails. No caller, no
  -- profile yet, second call of the day: all of them do nothing quietly. A
  -- counter that can throw is a counter that will one day take the app down
  -- with it, and nothing here is worth that.
  insert into app.activity (user_id, day)
  select auth.uid(), (now() at time zone 'Asia/Dubai')::date
  where auth.uid() is not null
    and exists (select 1 from public.profiles p where p.id = auth.uid())
  on conflict do nothing;
end;
$$;

comment on function public.record_activity is
  'Marks the caller present today. Idempotent, and silent when it cannot.';

-- ---------------------------------------------------------------------------
-- The overview
--
-- One row, the numbers worth seeing first.
--
-- The lifecycle counts come from transaction_events rather than from the
-- current state, because state is where a contract is now and the event log is
-- what happened. A contract sitting in 'completed' was accepted, delivered and
-- confirmed, and a funnel read off its current state would count it once and
-- lose the rest. The events are append-only, so this cannot drift.
-- ---------------------------------------------------------------------------

create or replace function public.admin_overview()
returns table (
  people                 bigint,
  verified               bigint,
  active_today           bigint,
  active_7d              bigint,
  active_30d             bigint,
  contracts              bigint,
  contracts_binding      bigint,
  contracts_confirmed    bigint,
  contracts_disputed     bigint,
  evidence_filed         bigint,
  disputes               bigint,
  disputes_open          bigint,
  proposals_issued       bigint,
  proposals_half_accepted bigint,
  proposals_accepted     bigint,
  escalated_to_human     bigint
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  perform app.assert_admin('the platform overview');

  return query
  select
    (select count(*) from app.real_profiles),
    (select count(*) from app.real_profiles p where p.identity_verified_at is not null),
    (select count(*) from app.activity a
      join app.real_profiles p on p.id = a.user_id where a.day = v_today),
    (select count(distinct a.user_id) from app.activity a
      join app.real_profiles p on p.id = a.user_id where a.day > v_today - 7),
    (select count(distinct a.user_id) from app.activity a
      join app.real_profiles p on p.id = a.user_id where a.day > v_today - 30),
    (select count(*) from app.real_transactions),
    (select count(distinct e.transaction_id) from public.transaction_events e
      join app.real_transactions t on t.id = e.transaction_id where e.event = 'accept'),
    (select count(distinct e.transaction_id) from public.transaction_events e
      join app.real_transactions t on t.id = e.transaction_id where e.event = 'confirm_delivery'),
    (select count(distinct e.transaction_id) from public.transaction_events e
      join app.real_transactions t on t.id = e.transaction_id where e.event = 'open_dispute'),
    (select count(*) from public.evidence v
      join app.real_transactions t on t.id = v.transaction_id),
    (select count(*) from public.disputes d
      join app.real_transactions t on t.id = d.transaction_id),
    (select count(*) from public.disputes d
      join app.real_transactions t on t.id = d.transaction_id
      where d.state in ('open', 'ai_review', 'proposal_issued', 'escalated', 'human_review')),
    (select count(*) from public.resolution_proposals r
      join public.disputes d on d.id = r.dispute_id
      join app.real_transactions t on t.id = d.transaction_id
      where r.source = 'ai'),
    -- One party said yes and the other has not. Worth seeing apart from the
    -- rest: it is the shape of a proposal that is about to be refused.
    (select count(*) from (
       select a.proposal_id from public.dispute_acceptances a
       join public.resolution_proposals r on r.id = a.proposal_id and r.source = 'ai'
       join public.disputes d on d.id = r.dispute_id
       join app.real_transactions t on t.id = d.transaction_id
       group by a.proposal_id having count(*) = 1
     ) one_side),
    (select count(*) from (
       select a.proposal_id from public.dispute_acceptances a
       join public.resolution_proposals r on r.id = a.proposal_id and r.source = 'ai'
       join public.disputes d on d.id = r.dispute_id
       join app.real_transactions t on t.id = d.transaction_id
       group by a.proposal_id having count(*) = 2
     ) agreed),
    (select count(distinct e.dispute_id) from public.dispute_events e
      join public.disputes d on d.id = e.dispute_id
      join app.real_transactions t on t.id = d.transaction_id
      where e.event = 'escalate');
end;
$$;

comment on function public.admin_overview is
  'The platform in one row. Counts only, never a name.';

-- ---------------------------------------------------------------------------
-- The daily series
--
-- Every day in the window appears, including the empty ones. A chart that
-- silently skips a day with nothing in it draws a line that climbs when the
-- truth was a flat week.
-- ---------------------------------------------------------------------------

create or replace function public.admin_daily(p_days integer default 30)
returns table (
  day       date,
  signups   bigint,
  active    bigint,
  contracts bigint,
  disputes  bigint
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 365);
begin
  perform app.assert_admin('the daily series');

  return query
  with days as (
    select generate_series(v_today - (v_days - 1), v_today, interval '1 day')::date as day
  )
  select
    d.day,
    (select count(*) from app.real_profiles p
      where (p.created_at at time zone 'Asia/Dubai')::date = d.day),
    (select count(*) from app.activity a
      join app.real_profiles p on p.id = a.user_id where a.day = d.day),
    (select count(*) from app.real_transactions t
      where (t.created_at at time zone 'Asia/Dubai')::date = d.day),
    (select count(*) from public.disputes x
      join app.real_transactions t on t.id = x.transaction_id
      where (x.opened_at at time zone 'Asia/Dubai')::date = d.day)
  from days d
  order by d.day;
end;
$$;

comment on function public.admin_daily is
  'Signups, actives, contracts and disputes per Dubai day, empty days included.';

-- ---------------------------------------------------------------------------
-- How the model is doing
--
-- Grouped by validation_outcome, which is the honest cut: 'accepted' here
-- means the pipeline accepted the model's output, not that anybody agreed with
-- it. Failures are in the same table on purpose. A model that often fails
-- validation is a signal, and hiding the failures would hide the signal.
-- ---------------------------------------------------------------------------

create or replace function public.admin_ai_quality()
returns table (
  outcome         text,
  calls           bigint,
  mean_confidence numeric,
  mean_latency_ms integer,
  last_call       timestamptz
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_admin('the model log');

  return query
  select
    l.validation_outcome,
    count(*),
    round(avg(l.confidence), 3),
    round(avg(l.latency_ms))::integer,
    max(l.created_at)
  from public.ai_call_log l
  -- Not filtered to real contracts, unlike everything else. A run that failed
  -- validation failed it the same way whoever the parties were, and the runs
  -- against test contracts are the only ones that have ever exercised the
  -- refusal branches. Dropping them would hide the evidence that the guards
  -- work.
  group by l.validation_outcome
  order by count(*) desc;
end;
$$;

comment on function public.admin_ai_quality is
  'Model runs grouped by what validation made of them, failures included.';

-- ---------------------------------------------------------------------------
-- Grants
--
-- To `authenticated` and no further. Every signed-in person can call these;
-- all but an operator gets an exception, which is the same shape as
-- claim_dispute and the rest. The sweep in schema.test.sql insists that
-- nothing in `public` is reachable with the key that ships inside the app, and
-- nothing here is an exception to that.
-- ---------------------------------------------------------------------------

revoke all on function public.record_activity() from public, anon;
revoke all on function public.admin_overview() from public, anon;
revoke all on function public.admin_daily(integer) from public, anon;
revoke all on function public.admin_ai_quality() from public, anon;

grant execute on function public.record_activity() to authenticated;
grant execute on function public.admin_overview() to authenticated;
grant execute on function public.admin_daily(integer) to authenticated;
grant execute on function public.admin_ai_quality() to authenticated;
