-- ---------------------------------------------------------------------------
-- 0003  Transactions, milestones, and the state machine
--
-- The transition table below is the same data as TRANSITIONS in
-- packages/core/src/transaction-machine.ts. Holding it in the database too is
-- deliberate defence in depth: a bug in the app, a stale mobile client, or a
-- direct SQL write cannot move a contract through a state change the product
-- does not allow.
-- ---------------------------------------------------------------------------

create table public.transactions (
  id                  uuid primary key default gen_random_uuid(),
  state               public.transaction_state not null default 'draft',

  buyer_id            uuid not null references public.profiles (id) on delete restrict,
  seller_id           uuid not null references public.profiles (id) on delete restrict,
  constraint transactions_distinct_parties check (buyer_id <> seller_id),

  description         text not null check (length(btrim(description)) between 1 and 500),
  terms               text not null check (length(btrim(terms)) between 1 and 10000),
  total_amount_fils   public.fils not null check (total_amount_fils > 0),

  created_by          uuid not null references public.profiles (id) on delete restrict,
  constraint transactions_creator_is_a_party check (created_by in (buyer_id, seller_id)),

  acceptance_deadline timestamptz,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  state_changed_at    timestamptz not null default now()
);

comment on table public.transactions is
  'A contract between two parties. v1 does not hold funds: total_amount_fils is what the parties agreed, not a balance TrustIQ custodies.';

create index transactions_buyer_idx  on public.transactions (buyer_id, state);
create index transactions_seller_idx on public.transactions (seller_id, state);
create index transactions_deadline_idx
  on public.transactions (acceptance_deadline)
  where state = 'pending_acceptance';

create trigger transactions_touch_updated_at
  before update on public.transactions
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Milestones
-- ---------------------------------------------------------------------------

create table public.milestones (
  id             uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  position       integer not null check (position >= 0),
  title          text not null check (length(btrim(title)) between 1 and 200),
  amount_fils    public.fils not null check (amount_fils > 0),
  due_at         timestamptz,
  delivered_at   timestamptz,
  accepted_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (transaction_id, position)
);

create index milestones_transaction_idx on public.milestones (transaction_id);

-- Milestones may not promise more than the contract is worth. Same principle as
-- allocate() in core: money that does not add up is a dispute waiting to happen.
create or replace function app.check_milestone_total()
returns trigger
language plpgsql
as $$
declare
  v_transaction_id uuid := coalesce(new.transaction_id, old.transaction_id);
  v_total          bigint;
  v_contract       bigint;
begin
  select coalesce(sum(m.amount_fils), 0) into v_total
  from public.milestones m
  where m.transaction_id = v_transaction_id;

  select t.total_amount_fils into v_contract
  from public.transactions t
  where t.id = v_transaction_id;

  if v_contract is not null and v_total > v_contract then
    raise exception 'milestones total % fils exceeds the contract total of % fils',
      v_total, v_contract
      using errcode = 'check_violation';
  end if;

  return null;
end;
$$;

create constraint trigger milestones_total_within_contract
  after insert or update or delete on public.milestones
  deferrable initially deferred
  for each row execute function app.check_milestone_total();

-- ---------------------------------------------------------------------------
-- Audit log of every state change
--
-- Append-only. This is the record that answers "who did what, and when" when a
-- contract is contested months later.
-- ---------------------------------------------------------------------------

create table public.transaction_events (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  from_state     public.transaction_state not null,
  event          public.transaction_event not null,
  to_state       public.transaction_state not null,
  actor          public.actor_role not null,
  actor_user_id  uuid references public.profiles (id) on delete set null,
  occurred_at    timestamptz not null default now()
);

create index transaction_events_transaction_idx
  on public.transaction_events (transaction_id, occurred_at);

create trigger transaction_events_immutable
  before update or delete on public.transaction_events
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- The transition table
-- ---------------------------------------------------------------------------

create table app.transaction_transitions (
  from_state      public.transaction_state not null,
  event           public.transaction_event not null,
  to_state        public.transaction_state not null,
  allowed_actors  public.actor_role[] not null check (cardinality(allowed_actors) > 0),
  describe        text not null,
  primary key (from_state, event)
);

insert into app.transaction_transitions (from_state, event, to_state, allowed_actors, describe) values
  ('draft',              'submit',              'pending_acceptance', '{buyer,seller}', 'The party who drafted the contract sends it to the other side.'),
  ('draft',              'withdraw',            'cancelled',          '{buyer,seller}', 'The drafting party abandons the contract before sending it.'),
  ('pending_acceptance', 'accept',              'active',             '{buyer,seller}', 'The receiving party agrees to the terms.'),
  ('pending_acceptance', 'decline',             'declined',           '{buyer,seller}', 'The receiving party refuses the terms.'),
  ('pending_acceptance', 'withdraw',            'cancelled',          '{buyer,seller}', 'The sending party pulls the contract back before it is accepted.'),
  ('pending_acceptance', 'expire',              'expired',            '{system}',       'The acceptance deadline passed with no answer.'),
  ('active',             'mark_delivered',      'delivered',          '{seller}',       'The seller declares the work delivered.'),
  ('active',             'open_dispute',        'disputed',           '{buyer,seller}', 'Either party raises a problem before delivery is declared.'),
  ('active',             'cancel_by_agreement', 'cancelled',          '{system}',       'Both parties agreed to call the contract off.'),
  ('delivered',          'confirm_delivery',    'completed',          '{buyer}',        'The buyer accepts the delivery.'),
  ('delivered',          'request_revision',    'active',             '{buyer}',        'The buyer sends the work back for changes.'),
  ('delivered',          'open_dispute',        'disputed',           '{buyer,seller}', 'Review broke down and a formal dispute is opened.'),
  ('disputed',           'resolve_dispute',     'resolved',           '{system}',       'The dispute reached a conclusion.');

-- ---------------------------------------------------------------------------
-- Actor resolution
--
-- The actor is derived from the authenticated user, never accepted as an
-- argument. A client that could name its own role could confirm a delivery on
-- the counterparty's behalf.
-- ---------------------------------------------------------------------------

create or replace function app.actor_for(p_buyer uuid, p_seller uuid)
returns public.actor_role
language sql
stable
as $$
  select case
    when auth.uid() is null      then 'system'::public.actor_role
    when auth.uid() = p_buyer    then 'buyer'::public.actor_role
    when auth.uid() = p_seller   then 'seller'::public.actor_role
    else null
  end;
$$;

-- ---------------------------------------------------------------------------
-- RLS helpers
--
-- SECURITY DEFINER so that a policy on a child table (milestones, evidence,
-- disputes) can ask "is the caller a party to this contract?" without
-- re-entering the transactions policy and recursing.
-- ---------------------------------------------------------------------------

create or replace function app.is_transaction_party(p_transaction_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.transactions t
    where t.id = p_transaction_id
      and (t.buyer_id = auth.uid() or t.seller_id = auth.uid())
  );
$$;

create or replace function app.transaction_is_draft(p_transaction_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.transactions t
    where t.id = p_transaction_id
      and t.state = 'draft'
  );
$$;

-- Deferred from 0002: this one needs the transactions table to exist.
create or replace function app.shares_transaction_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.transactions t
    where (t.buyer_id = auth.uid() and t.seller_id = p_other)
       or (t.seller_id = auth.uid() and t.buyer_id = p_other)
  );
$$;

-- You can see the counterparty of a contract you are on. Without this, the app
-- cannot show who it is you are dealing with.
create policy profiles_select_counterparty
  on public.profiles for select
  to authenticated
  using (app.shares_transaction_with(id));

-- ---------------------------------------------------------------------------
-- State change guard
--
-- Refuses any direct write to transactions.state. The only way through is
-- apply_transaction_event(), which sets a transaction-local flag first.
-- ---------------------------------------------------------------------------

create or replace function app.guard_transaction_state()
returns trigger
language plpgsql
as $$
begin
  if new.state is distinct from old.state
     and coalesce(current_setting('app.allow_state_change', true), '') <> 'on' then
    raise exception 'transactions.state must change through apply_transaction_event(), not a direct update'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger transactions_guard_state
  before update on public.transactions
  for each row execute function app.guard_transaction_state();

-- ---------------------------------------------------------------------------
-- apply_transaction_event
-- ---------------------------------------------------------------------------

-- Internal form: the actor is given rather than derived. Only other SECURITY
-- DEFINER functions call this, and only to act as `system` on the back of a
-- rule they have already enforced (for example, a dispute closing once both
-- parties accepted). It is never granted to a client role.
create or replace function app.apply_transaction_event_as(
  p_transaction_id uuid,
  p_event          public.transaction_event,
  p_actor          public.actor_role
)
returns public.transactions
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_txn   public.transactions;
  v_rule  app.transaction_transitions;
  v_actor public.actor_role := p_actor;
  v_buyer_ok  boolean;
  v_seller_ok boolean;
begin
  select * into v_txn
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception 'transaction % not found', p_transaction_id
      using errcode = 'no_data_found';
  end if;

  select * into v_rule
  from app.transaction_transitions
  where from_state = v_txn.state
    and event = p_event;

  if not found then
    raise exception '"%" is not a legal move from %', p_event, v_txn.state
      using errcode = 'check_violation';
  end if;

  if not (v_actor = any (v_rule.allowed_actors)) then
    raise exception 'the % may not fire "%" from % (allowed: %)',
      v_actor, p_event, v_txn.state, array_to_string(v_rule.allowed_actors, ', ')
      using errcode = 'insufficient_privilege';
  end if;

  -- A contract only becomes binding between verified identities.
  if p_event = 'accept' then
    select p.identity_verified_at is not null into v_buyer_ok
    from public.profiles p where p.id = v_txn.buyer_id;
    select p.identity_verified_at is not null into v_seller_ok
    from public.profiles p where p.id = v_txn.seller_id;

    if not (coalesce(v_buyer_ok, false) and coalesce(v_seller_ok, false)) then
      raise exception 'both parties must have a verified identity before a contract becomes active'
        using errcode = 'check_violation';
    end if;
  end if;

  perform set_config('app.allow_state_change', 'on', true);

  update public.transactions
  set state            = v_rule.to_state,
      state_changed_at = now()
  where id = p_transaction_id
  returning * into v_txn;

  perform set_config('app.allow_state_change', '', true);

  insert into public.transaction_events
    (transaction_id, from_state, event, to_state, actor, actor_user_id)
  values
    (p_transaction_id, v_rule.from_state, p_event, v_rule.to_state, v_actor, auth.uid());

  return v_txn;
end;
$$;

-- Public form: the actor is derived from the authenticated caller. This is what
-- the apps call.
create or replace function public.apply_transaction_event(
  p_transaction_id uuid,
  p_event          public.transaction_event
)
returns public.transactions
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_buyer  uuid;
  v_seller uuid;
  v_actor  public.actor_role;
begin
  select t.buyer_id, t.seller_id into v_buyer, v_seller
  from public.transactions t
  where t.id = p_transaction_id;

  if not found then
    raise exception 'transaction % not found', p_transaction_id
      using errcode = 'no_data_found';
  end if;

  v_actor := app.actor_for(v_buyer, v_seller);
  if v_actor is null then
    raise exception 'caller is not a party to transaction %', p_transaction_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.apply_transaction_event_as(p_transaction_id, p_event, v_actor);
end;
$$;

comment on function public.apply_transaction_event is
  'The only supported way for a client to change a transaction state. Derives the actor from the caller, validates against app.transaction_transitions, and appends to the audit log.';

revoke all on function public.apply_transaction_event(uuid, public.transaction_event) from public;
grant execute on function public.apply_transaction_event(uuid, public.transaction_event) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.transactions       enable row level security;
alter table public.milestones         enable row level security;
alter table public.transaction_events enable row level security;

create policy transactions_select_party
  on public.transactions for select
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

create policy transactions_insert_own_draft
  on public.transactions for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and auth.uid() in (buyer_id, seller_id)
    and state = 'draft'
  );

-- Terms are editable only while the contract is still a draft. Once it has been
-- sent, changing it under the other party is exactly the behaviour TrustIQ
-- exists to prevent.
create policy transactions_update_own_draft
  on public.transactions for update
  to authenticated
  using (state = 'draft' and created_by = auth.uid())
  with check (state = 'draft' and created_by = auth.uid());

-- No delete policy anywhere: contracts are withdrawn or cancelled, never erased.

create policy milestones_select_party
  on public.milestones for select
  to authenticated
  using (app.is_transaction_party(transaction_id));

create policy milestones_write_draft
  on public.milestones for all
  to authenticated
  using (app.is_transaction_party(transaction_id) and app.transaction_is_draft(transaction_id))
  with check (app.is_transaction_party(transaction_id) and app.transaction_is_draft(transaction_id));

create policy transaction_events_select_party
  on public.transaction_events for select
  to authenticated
  using (app.is_transaction_party(transaction_id));

-- No insert policy on transaction_events: rows arrive only through
-- apply_transaction_event(), which is SECURITY DEFINER.
