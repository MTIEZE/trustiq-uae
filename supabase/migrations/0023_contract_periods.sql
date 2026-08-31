-- ---------------------------------------------------------------------------
-- How long a contract lasts, and what happens when it runs out.
--
-- There was no vocabulary for any of this. A contract had an
-- `acceptance_deadline` and nothing else: no start, no end, no duration, no
-- renewal. Fine for a one-off piece of work, useless for the arrangement a
-- freelancer actually has with a regular client, which is the common shape
-- here.
--
-- Worse, `acceptance_deadline` was a promise nobody kept. The column existed,
-- the app read it, the screen showed it, and `expire` was declared a legal
-- system transition out of `pending_acceptance`. Nothing ever called it. A
-- contract sent and never answered sat waiting for ever, displaying a date that
-- had passed. That is worse than having no deadline: it says something and then
-- does not do it.
--
-- ---------------------------------------------------------------------------
-- Why a renewal is not a state
--
-- The transaction machine is about what has happened to the work: drafted,
-- accepted, delivered, confirmed. A renewal changes none of that. It extends
-- the period the same terms cover, and the contract carries on being exactly as
-- active as it was a minute earlier.
--
-- Forcing it in would mean a new value in `transaction_event`, which lives in
-- three languages behind a parity test, and `alter type ... add value` cannot
-- be used in the same transaction that adds it. All of that to model a
-- self-transition that says nothing.
--
-- A contract's periods are a list, so they are stored as one. `contract_
-- renewals` is append-only like every other record here: what the period was,
-- what it became, and on whose authority.
-- ---------------------------------------------------------------------------

alter table public.transactions
  add column if not exists starts_on date,
  add column if not exists ends_on   date,
  -- What the parties agreed happens at the end. Part of the terms, so it is
  -- recorded whether or not anything automates it.
  add column if not exists renewal   text not null default 'none';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_renewal_known'
  ) then
    alter table public.transactions
      add constraint transactions_renewal_known
        check (renewal in ('none', 'manual', 'automatic'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transactions_period_runs_forwards'
  ) then
    alter table public.transactions
      add constraint transactions_period_runs_forwards
        check (starts_on is null or ends_on is null or ends_on >= starts_on);
  end if;

  -- An open-ended contract has nothing to renew, and neither does one with no
  -- dates at all. Letting `renewal` say otherwise would put a promise on the
  -- record that nothing could ever keep.
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_renewal_needs_a_period'
  ) then
    alter table public.transactions
      add constraint transactions_renewal_needs_a_period
        check (renewal = 'none' or (starts_on is not null and ends_on is not null));
  end if;
end
$$;

comment on column public.transactions.starts_on is
  'When the arrangement begins. Null for work with no period, which is most one-off jobs.';
comment on column public.transactions.ends_on is
  'When the current period ends. Null means open-ended.';
comment on column public.transactions.renewal is
  'What the parties agreed happens at the end: none, manual, or automatic.';

-- ---------------------------------------------------------------------------
-- Every period the contract has run for
-- ---------------------------------------------------------------------------

create table if not exists public.contract_renewals (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions (id) on delete cascade,

  -- Where the period ended before, and where it ends now. Both kept, so the
  -- history reads as a chain rather than as a column that quietly moved.
  from_ends_on   date not null,
  to_ends_on     date not null check (to_ends_on > from_ends_on),

  -- 'automatic' is this file rolling it forward under the policy the parties
  -- agreed. 'agreed' is for a renewal both of them asked for, which nothing
  -- issues yet.
  source         text not null check (source in ('automatic', 'agreed')),

  renewed_at     timestamptz not null default now()
);

create index if not exists contract_renewals_transaction_idx
  on public.contract_renewals (transaction_id, renewed_at);

alter table public.contract_renewals enable row level security;

drop policy if exists contract_renewals_select_party on public.contract_renewals;
create policy contract_renewals_select_party
  on public.contract_renewals for select
  to authenticated
  using (app.is_transaction_party(transaction_id));

-- No insert, update or delete policy: the only thing that writes here is the
-- runner below, with the service role.
drop trigger if exists contract_renewals_immutable on public.contract_renewals;
create trigger contract_renewals_immutable
  before update or delete on public.contract_renewals
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Notices are not about a transition
--
-- The outbox only knew two kinds of thing, and both were something somebody
-- did. A deadline coming up is neither: nobody acted, and that is exactly why
-- it needs saying.
-- ---------------------------------------------------------------------------

-- Extended, not rewritten. Restating the list from memory is how 'milestone'
-- got dropped the first time this was written: 0018 had already added it, and
-- a fresh `check (source in (...))` silently removed it again.
alter table app.notifications
  drop constraint if exists notifications_source_check;

alter table app.notifications
  add constraint notifications_source_check
    check (source in ('transaction', 'dispute', 'milestone', 'schedule'));

-- ---------------------------------------------------------------------------
-- Making the deadline mean something
--
-- Fires `expire` on anything whose acceptance deadline has passed. As `system`,
-- which is the only actor the transition allows, and through the same function
-- every other transition goes through, so it lands in the audit log looking
-- like what it is.
-- ---------------------------------------------------------------------------

create or replace function public.expire_overdue_contracts()
returns table (transaction_id uuid, deadline timestamptz)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_row record;
begin
  perform app.assert_system_caller('expiring contracts');

  for v_row in
    select t.id, t.acceptance_deadline
    from public.transactions t
    where t.state = 'pending_acceptance'
      and t.acceptance_deadline is not null
      and t.acceptance_deadline <= now()
    order by t.acceptance_deadline
  loop
    perform app.apply_transaction_event_as(v_row.id, 'expire', 'system');
    transaction_id := v_row.id;
    deadline := v_row.acceptance_deadline;
    return next;
  end loop;
end;
$$;

comment on function public.expire_overdue_contracts is
  'Fires expire on contracts whose acceptance deadline has passed. Nothing called it before, so the column was a promise nobody kept.';

-- ---------------------------------------------------------------------------
-- Rolling a period forward
--
-- Only for contracts whose parties agreed to it, and only while the contract is
-- still live. A period ending on a contract nobody is working on any more is
-- not renewed; it just ended.
--
-- The new period is the same length as the one before, worked out with `age`
-- rather than in days, so a year stays a year across February.
-- ---------------------------------------------------------------------------

create or replace function public.renew_due_contracts()
returns table (transaction_id uuid, from_ends_on date, to_ends_on date)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_row   record;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_from  date;
  v_start date;
  v_next  date;
  v_step  interval;
  v_steps integer;
begin
  perform app.assert_system_caller('renewing contracts');

  for v_row in
    select t.id, t.starts_on, t.ends_on
    from public.transactions t
    where t.renewal = 'automatic'
      and t.ends_on is not null
      and t.ends_on <= v_today
      and t.state in ('active', 'delivered')
    order by t.ends_on
  loop
    v_from := v_row.ends_on;
    v_start := v_row.starts_on;
    v_next := v_from;
    v_steps := 0;

    -- Caught up in one run, not one period per run. If the scheduler was down
    -- for a week, or a month, the contract should not sit in a period that
    -- ended long ago while a daily job walks it forward a year at a time. Every
    -- period it passes through is recorded, so the chain stays complete.
    while v_next <= v_today and v_steps < 200 loop
      v_step := age(v_next, v_start);
      -- A period so short it would not move the date would spin here for ever.
      if v_step <= interval '0' then v_step := interval '1 day'; end if;

      v_start := v_next;
      v_next := v_next + v_step;
      v_steps := v_steps + 1;

      insert into public.contract_renewals
        (transaction_id, from_ends_on, to_ends_on, source)
      values (v_row.id, v_start, v_next, 'automatic');
    end loop;

    if v_steps = 0 then continue; end if;

    update public.transactions
    set starts_on = v_start,
        ends_on   = v_next,
        updated_at = now()
    where id = v_row.id;

    -- Both parties, and neither of them has to do anything about it, which is
    -- the whole point of having agreed to it in advance.
    insert into app.notifications (recipient_id, transaction_id, source, event, actor, needs_you)
    select p, v_row.id, 'schedule', 'period_renewed', 'system', false
    from (select buyer_id from public.transactions where id = v_row.id
          union select seller_id from public.transactions where id = v_row.id) as parties(p);

    transaction_id := v_row.id;
    from_ends_on := v_from;
    to_ends_on := v_next;
    return next;
  end loop;
end;
$$;

comment on function public.renew_due_contracts is
  'Rolls automatic contracts forward by the length of their own period, and records each one.';

-- ---------------------------------------------------------------------------
-- Saying so before it happens
--
-- Two kinds of warning, both written into the same outbox everything else
-- uses, so they arrive in the app and by email without any new plumbing.
--
-- Written once each. The guard is a `not exists` rather than a unique index,
-- because the same contract legitimately gets a fresh period notice after every
-- renewal, and the window moves with `ends_on`.
-- ---------------------------------------------------------------------------

create or replace function public.write_deadline_notices(
  p_accept_within interval default interval '2 days',
  p_period_within interval default interval '14 days'
)
returns table (event text, written integer)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_count integer;
begin
  perform app.assert_system_caller('writing deadline notices');

  -- An acceptance deadline about to pass. The person who has to act is the one
  -- who did not send it, and they are the only one this is work for.
  insert into app.notifications (recipient_id, transaction_id, source, event, actor, needs_you)
  select
    party.id,
    t.id,
    'schedule',
    'acceptance_expiring',
    'system',
    party.id <> t.created_by
  from public.transactions t
  cross join lateral (
    select t.buyer_id as id union select t.seller_id
  ) party
  where t.state = 'pending_acceptance'
    and t.acceptance_deadline is not null
    and t.acceptance_deadline > now()
    and t.acceptance_deadline <= now() + p_accept_within
    and not exists (
      select 1 from app.notifications n
      where n.transaction_id = t.id
        and n.recipient_id = party.id
        and n.event = 'acceptance_expiring'
    );

  get diagnostics v_count = row_count;
  event := 'acceptance_expiring';
  written := v_count;
  return next;

  -- A period about to end. Whether that is work depends on what they agreed:
  -- a manual renewal needs a decision from both of them, and the other two do
  -- not need anything from anybody.
  insert into app.notifications (recipient_id, transaction_id, source, event, actor, needs_you)
  select
    party.id,
    t.id,
    'schedule',
    'period_ending',
    'system',
    t.renewal = 'manual'
  from public.transactions t
  cross join lateral (
    select t.buyer_id as id union select t.seller_id
  ) party
  where t.state in ('active', 'delivered')
    and t.ends_on is not null
    and t.ends_on >= v_today
    and t.ends_on <= v_today + p_period_within
    and not exists (
      select 1 from app.notifications n
      where n.transaction_id = t.id
        and n.recipient_id = party.id
        and n.event = 'period_ending'
        -- Reset by a renewal: the window is tied to this period, not to the
        -- contract, so the next one gets its own warning.
        and n.created_at > (t.ends_on - p_period_within - interval '1 day')
    );

  get diagnostics v_count = row_count;
  event := 'period_ending';
  written := v_count;
  return next;
end;
$$;

comment on function public.write_deadline_notices is
  'Warns before an acceptance deadline passes and before a period ends. Written once each, and again after a renewal moves the window.';

-- ---------------------------------------------------------------------------
-- Grants
--
-- All three are the scheduler's, reached with the service role. Nothing here
-- is a client API: a person cannot expire somebody else's contract, and cannot
-- renew their own.
-- ---------------------------------------------------------------------------

revoke all on function public.expire_overdue_contracts() from public, anon, authenticated;
revoke all on function public.renew_due_contracts() from public, anon, authenticated;
revoke all on function public.write_deadline_notices(interval, interval) from public, anon, authenticated;

grant execute on function public.expire_overdue_contracts() to service_role;
grant execute on function public.renew_due_contracts() to service_role;
grant execute on function public.write_deadline_notices(interval, interval) to service_role;
