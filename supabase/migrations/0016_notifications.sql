-- ---------------------------------------------------------------------------
-- 0016  Telling somebody that something needs them
--
-- Nothing ever reached a person who was not already looking at the app. A
-- contract addressed to you waited for you to open it and notice. On a product
-- where the whole point is that the other party has to act, that pushed every
-- transaction back onto WhatsApp, which is the thing TrustIQ was meant to
-- replace as the place a deal lives.
--
-- Two decisions shape everything here.
--
-- **An outbox, not a send.** No trigger in this file talks to anything outside
-- the database. A trigger that called a mail provider would tie the success of
-- accepting a contract to that provider being up: Brevo has a bad afternoon and
-- the state machine starts refusing legal transitions. The record must never
-- depend on the postman. So an event writes a row, and something else drains
-- it, later, and can fail and retry without any of that reaching the parties.
--
-- **The database records what happened, not what to say.** A row carries the
-- event and the machine it came from, never a sentence. The app already renders
-- every state and transition in English and Arabic; an English string in a
-- column would be a third copy of that vocabulary, out of reach of the
-- translation tests, and unreadable to half the intended users.
--
-- These rows are not part of the record. transaction_events and dispute_events
-- are the record and are append-only; a notification is a delivery job about
-- one, and it has to be markable as read and as sent. That is why no
-- forbid_mutation trigger is attached here.
-- ---------------------------------------------------------------------------

create table app.notifications (
  id             bigint generated always as identity primary key,

  recipient_id   uuid not null references public.profiles (id) on delete cascade,

  -- Which thing it is about. A dispute notification carries both, so the app
  -- can open the contract and land on its dispute.
  transaction_id uuid references public.transactions (id) on delete cascade,
  dispute_id     uuid references public.disputes (id) on delete cascade,

  -- 'transaction' or 'dispute': which machine the event belongs to. The event
  -- name is stored as text rather than as the enum, because the two enums
  -- share names and a single column cannot be both.
  source         text not null check (source in ('transaction', 'dispute')),
  event          text not null,

  -- Who did it, as a role. Needed to render the sentence, and it cannot be
  -- inferred from the recipient: for a system transition both parties are
  -- told and neither of them acted.
  actor          public.actor_role not null,

  -- Whether the recipient is the one who now has to do something, as opposed
  -- to being told about something that happened. The app sorts on this, and
  -- an email is only worth sending for the first kind.
  needs_you      boolean not null,

  created_at     timestamptz not null default now(),
  read_at        timestamptz,

  -- Delivery, tracked per channel so a failed email does not hide the fact
  -- that the person saw it in the app anyway.
  emailed_at     timestamptz,
  email_error    text,

  constraint notifications_about_something check (
    transaction_id is not null or dispute_id is not null
  )
);

comment on table app.notifications is
  'Outbox. Written by triggers on the event tables, drained by whatever sends. Carries the event, never a sentence: the app and the sender each render it in the reader''s language.';

create index notifications_recipient_idx
  on app.notifications (recipient_id, created_at desc);

-- Partial, because the sender only ever asks for this one slice and it stays
-- small: everything already sent falls out of the index.
create index notifications_unsent_idx
  on app.notifications (created_at)
  where needs_you and emailed_at is null and email_error is null;

-- ---------------------------------------------------------------------------
-- Which events are worth a notification, and to whom
--
-- Everybody party to the thing, except whoever caused it. Nobody needs telling
-- about their own move.
--
-- `needs_you` is the interesting column. It says whether the next move belongs
-- to the person being told. It is written here rather than derived in the app
-- because the same fact would then be computed in Dart, in the email sender,
-- and eventually in a push payload, and those three would disagree.
-- ---------------------------------------------------------------------------

create or replace function app.transaction_event_needs_them(p_event text)
returns boolean
language sql
immutable
as $$
  -- After these, the person being told is the one holding the next move.
  --
  -- Read from the recipient rather than from the event, which is where the
  -- first version of this went wrong. `accept` felt like it belonged: it does
  -- not. The person told about an acceptance is the one who sent the contract,
  -- and they now wait for the work. `request_revision` was missing for the
  -- mirror reason: it reads like a comment and it is a job of work.
  select p_event in (
    'submit',            -- they must accept or decline
    'mark_delivered',    -- they must confirm it or ask for changes
    'request_revision',  -- they must do the work again
    'open_dispute'       -- they owe their account of what happened
  );
$$;

create or replace function app.dispute_event_needs_them(p_event text)
returns boolean
language sql
immutable
as $$
  -- open_dispute: they owe their account. issue_proposal: they must accept or
  -- refuse. The rest is news.
  select p_event in ('open_dispute', 'issue_proposal');
$$;

create or replace function app.notify_on_transaction_event()
returns trigger
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_txn public.transactions;
begin
  select * into v_txn from public.transactions t where t.id = new.transaction_id;

  insert into app.notifications
    (recipient_id, transaction_id, source, event, actor, needs_you)
  select
    party,
    new.transaction_id,
    'transaction',
    new.event::text,
    new.actor,
    app.transaction_event_needs_them(new.event::text)
  from (values (v_txn.buyer_id), (v_txn.seller_id)) as parties(party)
  -- actor_user_id is null for a system transition, and then both parties hear
  -- about it, which is correct: neither of them did it.
  where party is distinct from new.actor_user_id;

  return null;
end;
$$;

create or replace function app.notify_on_dispute_event()
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
  select d.transaction_id, t.buyer_id, t.seller_id
  into v_txn_id, v_buyer, v_seller
  from public.disputes d
  join public.transactions t on t.id = d.transaction_id
  where d.id = new.dispute_id;

  insert into app.notifications
    (recipient_id, transaction_id, dispute_id, source, event, actor, needs_you)
  select
    party,
    v_txn_id,
    new.dispute_id,
    'dispute',
    new.event::text,
    new.actor,
    app.dispute_event_needs_them(new.event::text)
  from (values (v_buyer), (v_seller)) as parties(party)
  where party is distinct from new.actor_user_id;

  return null;
end;
$$;

-- AFTER, so a notification can never be the reason a transition fails. FOR
-- EACH ROW on the event tables rather than on the state tables, because the
-- event is the thing worth telling somebody about and it is written exactly
-- once per transition.
create trigger transaction_events_notify
  after insert on public.transaction_events
  for each row execute function app.notify_on_transaction_event();

create trigger dispute_events_notify
  after insert on public.dispute_events
  for each row execute function app.notify_on_dispute_event();

-- ---------------------------------------------------------------------------
-- Reading them
-- ---------------------------------------------------------------------------

create or replace function public.my_notifications(p_limit integer default 50)
returns table (
  id             bigint,
  transaction_id uuid,
  dispute_id     uuid,
  source         text,
  event          text,
  actor          public.actor_role,
  needs_you      boolean,
  created_at     timestamptz,
  read_at        timestamptz
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select n.id, n.transaction_id, n.dispute_id, n.source, n.event, n.actor,
         n.needs_you, n.created_at, n.read_at
  from app.notifications n
  where n.recipient_id = auth.uid()
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

comment on function public.my_notifications is
  'Only ever your own. The table has no client grant, so this function is the whole surface.';

create or replace function public.mark_notifications_read(p_before timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_rows integer;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  -- p_before so that opening the list marks what was on screen, and not
  -- something that arrived while it was being read.
  update app.notifications
  set read_at = now()
  where recipient_id = auth.uid()
    and read_at is null
    and (p_before is null or created_at <= p_before);

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- From PUBLIC as well as from anon: Postgres grants EXECUTE to PUBLIC on every
-- new function on its own, and anon is a member of PUBLIC, so revoking from
-- anon alone leaves the grant standing through the group.
-- ---------------------------------------------------------------------------

revoke all on function public.my_notifications(integer) from public, anon;
revoke all on function public.mark_notifications_read(timestamptz) from public, anon;
revoke all on function app.transaction_event_needs_them(text) from public, anon, authenticated;
revoke all on function app.dispute_event_needs_them(text) from public, anon, authenticated;

grant execute on function public.my_notifications(integer) to authenticated;
grant execute on function public.mark_notifications_read(timestamptz) to authenticated;
