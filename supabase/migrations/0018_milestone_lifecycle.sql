-- ---------------------------------------------------------------------------
-- 0018  Work that is agreed a stage at a time
--
-- The milestones table has been here since 0003, with delivered_at and
-- accepted_at, a constraint keeping the stages inside the contract total, and
-- a policy letting both parties read them. Nothing ever set those two columns
-- and nothing in the app ever created a milestone. The shape was right and the
-- lifecycle was never written.
--
-- A freelance contract is not one delivery. Three concepts, a revision round,
-- final files: the client agrees to each as it lands, and the value of that
-- agreement is that it was recorded when both sides still agreed.
--
-- What this deliberately does NOT do is touch the dispute machine. A dispute
-- is still about the whole contract, with the milestone history as evidence
-- inside it. Splitting disputes per stage would mean asking what
-- disputed_amount_fils means on a contract where stage seven went wrong, and
-- the answer only matters once TrustIQ holds money. v1 holds none: milestones
-- here are about recorded agreement on progress, not about releasing funds.
-- That is also why there is no partial settlement anywhere in this file.
--
-- Three transitions, written as three guarded functions rather than as a
-- fourth table of rules. The tension with the rest of this schema is real and
-- worth naming: transaction and dispute states are enums driven by a data
-- table that a parity test compares against TypeScript and Dart. A milestone
-- has no state column at all, only two timestamps, and three rules over two
-- nullable columns is a table nobody would read.
-- ---------------------------------------------------------------------------

-- Milestone moves are worth telling the other party about, so the outbox has
-- to be able to carry them.
alter table app.notifications
  drop constraint notifications_source_check;

alter table app.notifications
  add constraint notifications_source_check
    check (source in ('transaction', 'dispute', 'milestone'));

alter table app.notifications
  add column milestone_id uuid references public.milestones (id) on delete cascade;

-- ---------------------------------------------------------------------------
-- The record of stages
--
-- Append only, like every other event table here. delivered_at and accepted_at
-- say where a milestone stands now; this says how it got there, including the
-- rounds that were sent back.
-- ---------------------------------------------------------------------------

create table public.milestone_events (
  id            bigint generated always as identity primary key,
  milestone_id  uuid not null references public.milestones (id) on delete cascade,
  event         text not null check (event in ('deliver', 'accept', 'request_revision')),
  actor         public.party_role not null,
  actor_user_id uuid references public.profiles (id) on delete set null,
  occurred_at   timestamptz not null default now()
);

comment on table public.milestone_events is
  'Every stage move, written once. A milestone sent back twice is two entries and the fact that it took three attempts survives.';

create index milestone_events_milestone_idx
  on public.milestone_events (milestone_id, occurred_at);

alter table public.milestone_events enable row level security;

create policy milestone_events_select_party
  on public.milestone_events for select
  to authenticated
  using (exists (
    select 1 from public.milestones m
    where m.id = milestone_events.milestone_id
      and app.is_transaction_party(m.transaction_id)
  ));

create trigger milestone_events_immutable
  before update or delete on public.milestone_events
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Moving a stage
--
-- The contract-level transitions these fire carry the real actor, not
-- 'system'. The seller did deliver the last stage and the buyer did accept it;
-- recording those as system moves would put TrustIQ's name on decisions two
-- people made.
-- ---------------------------------------------------------------------------

create or replace function app.milestone_context(p_milestone_id uuid)
returns table (
  transaction_id uuid,
  state          public.transaction_state,
  role           public.party_role,
  delivered_at   timestamptz,
  accepted_at    timestamptz
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select t.id, t.state,
         case when t.buyer_id = auth.uid() then 'buyer'::public.party_role
              else 'seller'::public.party_role end,
         m.delivered_at, m.accepted_at
  from public.milestones m
  join public.transactions t on t.id = m.transaction_id
  where m.id = p_milestone_id
    and auth.uid() in (t.buyer_id, t.seller_id);
$$;

create or replace function public.deliver_milestone(p_milestone_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  c record;
  v_left integer;
begin
  select * into c from app.milestone_context(p_milestone_id);

  -- One answer for "no such milestone" and for "not yours". The other way
  -- round, this reports whether an id exists to anybody who guesses one.
  if c.transaction_id is null then
    raise exception 'no milestone of yours with that id' using errcode = 'no_data_found';
  end if;
  if c.role <> 'seller' then
    raise exception 'only the seller delivers a stage' using errcode = 'insufficient_privilege';
  end if;
  if c.state <> 'active' then
    raise exception 'stages move only while the contract is active, and this one is %', c.state
      using errcode = 'check_violation';
  end if;
  if c.delivered_at is not null then
    raise exception 'that stage is already delivered' using errcode = 'check_violation';
  end if;

  update public.milestones set delivered_at = now() where id = p_milestone_id;

  insert into public.milestone_events (milestone_id, event, actor, actor_user_id)
  values (p_milestone_id, 'deliver', 'seller', auth.uid());

  select count(*) into v_left
  from public.milestones m
  where m.transaction_id = c.transaction_id and m.delivered_at is null;

  -- The last stage delivered is the work delivered. Fired as the seller
  -- because the seller is who did it.
  if v_left = 0 then
    perform app.apply_transaction_event_as(c.transaction_id, 'mark_delivered', 'seller');
  end if;
end;
$$;

create or replace function public.accept_milestone(p_milestone_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  c record;
  v_left integer;
begin
  select * into c from app.milestone_context(p_milestone_id);

  if c.transaction_id is null then
    raise exception 'no milestone of yours with that id' using errcode = 'no_data_found';
  end if;
  if c.role <> 'buyer' then
    raise exception 'only the buyer accepts a stage' using errcode = 'insufficient_privilege';
  end if;
  if c.delivered_at is null then
    raise exception 'that stage has not been delivered yet' using errcode = 'check_violation';
  end if;
  if c.accepted_at is not null then
    raise exception 'that stage is already accepted' using errcode = 'check_violation';
  end if;

  update public.milestones set accepted_at = now() where id = p_milestone_id;

  insert into public.milestone_events (milestone_id, event, actor, actor_user_id)
  values (p_milestone_id, 'accept', 'buyer', auth.uid());

  select count(*) into v_left
  from public.milestones m
  where m.transaction_id = c.transaction_id and m.accepted_at is null;

  -- Accepting the last stage is accepting the work. Asking the buyer to
  -- confirm the contract as well, having just confirmed every part of it,
  -- would be a second signature for the same decision.
  if v_left = 0 then
    perform app.apply_transaction_event_as(c.transaction_id, 'confirm_delivery', 'buyer');
  end if;
end;
$$;

create or replace function public.request_milestone_revision(p_milestone_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  c record;
begin
  select * into c from app.milestone_context(p_milestone_id);

  if c.transaction_id is null then
    raise exception 'no milestone of yours with that id' using errcode = 'no_data_found';
  end if;
  if c.role <> 'buyer' then
    raise exception 'only the buyer sends a stage back' using errcode = 'insufficient_privilege';
  end if;
  if c.delivered_at is null then
    raise exception 'that stage has not been delivered yet' using errcode = 'check_violation';
  end if;
  if c.accepted_at is not null then
    raise exception 'that stage was accepted and cannot be sent back'
      using errcode = 'check_violation';
  end if;

  -- delivered_at is cleared because the stage genuinely is not delivered any
  -- more. What happened is not lost: milestone_events keeps every round, so a
  -- stage that took three attempts still reads as three attempts.
  update public.milestones set delivered_at = null where id = p_milestone_id;

  insert into public.milestone_events (milestone_id, event, actor, actor_user_id)
  values (p_milestone_id, 'request_revision', 'buyer', auth.uid());

  -- If the whole contract had reached delivered on the strength of this stage,
  -- it has to come back too.
  if c.state = 'delivered' then
    perform app.apply_transaction_event_as(c.transaction_id, 'request_revision', 'buyer');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Telling the other party
-- ---------------------------------------------------------------------------

create or replace function app.notify_on_milestone_event()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_txn_id uuid;
  v_buyer  uuid;
  v_seller uuid;
begin
  select m.transaction_id, t.buyer_id, t.seller_id
  into v_txn_id, v_buyer, v_seller
  from public.milestones m
  join public.transactions t on t.id = m.transaction_id
  where m.id = new.milestone_id;

  insert into app.notifications
    (recipient_id, transaction_id, milestone_id, source, event, actor, needs_you)
  select
    party,
    v_txn_id,
    new.milestone_id,
    'milestone',
    new.event,
    new.actor::text::public.actor_role,
    -- A stage delivered is the buyer's turn to look at it; a stage sent back
    -- is the seller's turn to redo it. A stage accepted is neither: it is the
    -- good news that there is nothing to do.
    new.event in ('deliver', 'request_revision')
  from (values (v_buyer), (v_seller)) as parties(party)
  where party is distinct from new.actor_user_id;

  return null;
end;
$$;

create trigger milestone_events_notify
  after insert on public.milestone_events
  for each row execute function app.notify_on_milestone_event();

-- The outbox reader joins transactions, and a milestone notification carries
-- one, so nothing there changes.

-- ---------------------------------------------------------------------------
-- Grants
--
-- From PUBLIC as well as anon: Postgres grants EXECUTE to PUBLIC on every new
-- function, and anon is a member of PUBLIC.
-- ---------------------------------------------------------------------------

revoke all on function public.deliver_milestone(uuid) from public, anon;
revoke all on function public.accept_milestone(uuid) from public, anon;
revoke all on function public.request_milestone_revision(uuid) from public, anon;
revoke all on function app.milestone_context(uuid) from public, anon, authenticated;

grant execute on function public.deliver_milestone(uuid) to authenticated;
grant execute on function public.accept_milestone(uuid) to authenticated;
grant execute on function public.request_milestone_revision(uuid) to authenticated;
