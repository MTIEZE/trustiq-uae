-- ---------------------------------------------------------------------------
-- 0005  Disputes, AI proposals, and acceptance
--
-- This file encodes the product's central decision: the AI proposes, it does
-- not rule. A dispute closes only when both parties have accepted the same
-- proposal. The database enforces that rather than trusting the application:
--
--   * acceptance is a row with primary key (proposal_id, role), so a replayed
--     request is a duplicate-key no-op rather than a second vote;
--   * the transition to `accepted` is fired by a SECURITY DEFINER function that
--     first counts two distinct roles;
--   * an allocation that does not sum to the disputed amount fails a CHECK;
--   * a finding citing evidence nobody submitted fails a foreign key.
-- ---------------------------------------------------------------------------

create table public.disputes (
  id               uuid primary key default gen_random_uuid(),
  transaction_id   uuid not null references public.transactions (id) on delete cascade,
  state            public.dispute_state not null default 'open',

  opened_by        uuid not null references public.profiles (id) on delete restrict,
  opened_by_role   public.party_role not null,

  buyer_claim      text check (length(btrim(buyer_claim)) between 1 and 5000),
  seller_claim     text check (length(btrim(seller_claim)) between 1 and 5000),

  -- Copied from the contract when the dispute opens, so a later edit to the
  -- contract cannot retroactively change what was under dispute.
  disputed_amount_fils public.fils not null check (disputed_amount_fils > 0),

  opened_at        timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  state_changed_at timestamptz not null default now()
);

comment on table public.disputes is
  'One contested delivery. At most one dispute per transaction may be open at a time.';

create unique index disputes_one_active_per_transaction
  on public.disputes (transaction_id)
  where state not in ('accepted', 'resolved_by_human', 'withdrawn');

create index disputes_transaction_idx on public.disputes (transaction_id);
create index disputes_state_idx       on public.disputes (state) where state in ('escalated', 'human_review');

create trigger disputes_touch_updated_at
  before update on public.disputes
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Proposals
--
-- Append-only. The current proposal for a dispute is the most recent one.
-- Acceptances point at a specific proposal, so "both accepted" can never mean
-- "each accepted a different version".
-- ---------------------------------------------------------------------------

create table public.resolution_proposals (
  id                   uuid primary key default gen_random_uuid(),
  dispute_id           uuid not null references public.disputes (id) on delete cascade,

  source               text not null check (source in ('ai', 'human')),
  decision             public.resolution_decision not null,
  summary              text not null check (length(btrim(summary)) between 1 and 5000),

  -- Denormalised from the dispute so the balance rule can be a plain CHECK.
  -- A trigger below verifies it still matches the dispute at insert time.
  disputed_amount_fils public.fils not null check (disputed_amount_fils > 0),
  seller_amount_fils   public.fils not null check (seller_amount_fils >= 0),
  buyer_amount_fils    public.fils not null check (buyer_amount_fils >= 0),

  -- The invariant that keeps a ledger balanced. Same rule as validateProposal's
  -- ALLOCATION_MISMATCH in packages/core/src/resolution.ts.
  constraint proposal_allocation_balances
    check (seller_amount_fils + buyer_amount_fils = disputed_amount_fils),

  -- A decision must agree with its own numbers.
  constraint proposal_decision_matches_allocation check (
    (decision = 'release_to_seller' and buyer_amount_fils = 0  and seller_amount_fils > 0)
    or (decision = 'refund_to_buyer' and seller_amount_fils = 0 and buyer_amount_fils > 0)
    or (decision = 'split'           and seller_amount_fils > 0 and buyer_amount_fils > 0)
  ),

  confidence           numeric(4, 3) check (confidence >= 0 and confidence <= 1),
  model_id             text,
  issued_at            timestamptz not null default now(),

  -- An AI proposal must record which model produced it and how sure it was.
  -- A human resolution must not pretend to either.
  constraint proposal_ai_is_attributed check (
    (source = 'ai'    and model_id is not null and confidence is not null)
    or (source = 'human' and model_id is null and confidence is null)
  )
);

create index resolution_proposals_dispute_idx
  on public.resolution_proposals (dispute_id, issued_at desc);

create trigger resolution_proposals_immutable
  before update or delete on public.resolution_proposals
  for each row execute function app.forbid_mutation();

create or replace function app.check_proposal_amount()
returns trigger
language plpgsql
as $$
declare
  v_disputed bigint;
begin
  select d.disputed_amount_fils into v_disputed
  from public.disputes d
  where d.id = new.dispute_id;

  if new.disputed_amount_fils <> v_disputed then
    raise exception 'proposal is for % fils but dispute % is over % fils',
      new.disputed_amount_fils, new.dispute_id, v_disputed
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger resolution_proposals_amount_matches_dispute
  before insert on public.resolution_proposals
  for each row execute function app.check_proposal_amount();

-- ---------------------------------------------------------------------------
-- Grounded findings
--
-- Every statement in a proposal must cite at least one piece of evidence that
-- was actually submitted. The foreign key makes a hallucinated citation
-- unstorable; the trigger makes an uncited statement unstorable.
-- ---------------------------------------------------------------------------

create table public.resolution_findings (
  id          uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.resolution_proposals (id) on delete cascade,
  position    integer not null check (position >= 0),
  statement   text not null check (length(btrim(statement)) between 1 and 2000),
  unique (proposal_id, position)
);

create table public.resolution_finding_evidence (
  finding_id  uuid not null references public.resolution_findings (id) on delete cascade,
  evidence_id uuid not null references public.evidence (id) on delete restrict,
  primary key (finding_id, evidence_id)
);

create index resolution_findings_proposal_idx on public.resolution_findings (proposal_id);

create or replace function app.check_finding_is_grounded()
returns trigger
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.resolution_finding_evidence fe
  where fe.finding_id = new.id;

  if v_count = 0 then
    raise exception 'finding % cites no evidence; a statement about someone''s money must be grounded', new.id
      using errcode = 'check_violation';
  end if;

  return null;
end;
$$;

-- Deferred: the finding row and its citations are inserted in the same
-- transaction, so the check has to run at commit rather than at statement time.
create constraint trigger resolution_findings_must_be_grounded
  after insert on public.resolution_findings
  deferrable initially deferred
  for each row execute function app.check_finding_is_grounded();

-- ---------------------------------------------------------------------------
-- Acceptance
--
-- The primary key is the idempotency guarantee: the same party accepting twice
-- is a duplicate key, not a second vote.
-- ---------------------------------------------------------------------------

create table public.dispute_acceptances (
  proposal_id uuid not null references public.resolution_proposals (id) on delete cascade,
  role        public.party_role not null,
  user_id     uuid not null references public.profiles (id) on delete restrict,
  accepted_at timestamptz not null default now(),
  primary key (proposal_id, role)
);

create trigger dispute_acceptances_immutable
  before update or delete on public.dispute_acceptances
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Dispute audit log
-- ---------------------------------------------------------------------------

create table public.dispute_events (
  id            bigint generated always as identity primary key,
  dispute_id    uuid not null references public.disputes (id) on delete cascade,
  from_state    public.dispute_state not null,
  event         public.dispute_event not null,
  to_state      public.dispute_state not null,
  actor         public.actor_role not null,
  actor_user_id uuid references public.profiles (id) on delete set null,
  occurred_at   timestamptz not null default now()
);

create index dispute_events_dispute_idx on public.dispute_events (dispute_id, occurred_at);

create trigger dispute_events_immutable
  before update or delete on public.dispute_events
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Dispute transition table
-- ---------------------------------------------------------------------------

create table app.dispute_transitions (
  from_state     public.dispute_state not null,
  event          public.dispute_event not null,
  to_state       public.dispute_state not null,
  allowed_actors public.actor_role[] not null check (cardinality(allowed_actors) > 0),
  describe       text not null,
  primary key (from_state, event)
);

insert into app.dispute_transitions (from_state, event, to_state, allowed_actors, describe) values
  ('open',            'submit_for_ai',          'ai_review',         '{system}',       'Claims and evidence are complete, so the case goes to the model.'),
  ('open',            'withdraw_dispute',       'withdrawn',         '{buyer,seller}', 'The party who opened the dispute drops it.'),
  ('ai_review',       'issue_proposal',         'proposal_issued',   '{system}',       'The model returned a resolution that passed validation.'),
  ('ai_review',       'escalate',               'escalated',         '{system}',       'Confidence too low or amount above the automatic ceiling.'),
  ('proposal_issued', 'accept_proposal',        'accepted',          '{system}',       'Both parties accepted. Fired only once the second acceptance lands.'),
  ('proposal_issued', 'reject_proposal',        'escalated',         '{buyer,seller}', 'Either party refuses. One refusal is enough.'),
  ('escalated',       'assign_reviewer',        'human_review',      '{system}',       'A human reviewer picks up the case.'),
  ('human_review',    'issue_human_resolution', 'resolved_by_human', '{system}',       'The reviewer issued a decision.');

-- ---------------------------------------------------------------------------
-- Guard and transition function
-- ---------------------------------------------------------------------------

create or replace function app.guard_dispute_state()
returns trigger
language plpgsql
as $$
begin
  if new.state is distinct from old.state
     and coalesce(current_setting('app.allow_state_change', true), '') <> 'on' then
    raise exception 'disputes.state must change through apply_dispute_event(), not a direct update'
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;

create trigger disputes_guard_state
  before update on public.disputes
  for each row execute function app.guard_dispute_state();

create or replace function app.is_dispute_party(p_dispute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.disputes d
    join public.transactions t on t.id = d.transaction_id
    where d.id = p_dispute_id
      and (t.buyer_id = auth.uid() or t.seller_id = auth.uid())
  );
$$;

create or replace function app.dispute_actor(p_dispute_id uuid)
returns public.actor_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.actor_for(t.buyer_id, t.seller_id)
  from public.disputes d
  join public.transactions t on t.id = d.transaction_id
  where d.id = p_dispute_id;
$$;

create or replace function app.apply_dispute_event_as(
  p_dispute_id uuid,
  p_event      public.dispute_event,
  p_actor      public.actor_role
)
returns public.disputes
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_dispute public.disputes;
  v_rule    app.dispute_transitions;
begin
  select * into v_dispute
  from public.disputes
  where id = p_dispute_id
  for update;

  if not found then
    raise exception 'dispute % not found', p_dispute_id using errcode = 'no_data_found';
  end if;

  select * into v_rule
  from app.dispute_transitions
  where from_state = v_dispute.state and event = p_event;

  if not found then
    raise exception '"%" is not a legal move from %', p_event, v_dispute.state
      using errcode = 'check_violation';
  end if;

  if not (p_actor = any (v_rule.allowed_actors)) then
    raise exception 'the % may not fire "%" from % (allowed: %)',
      p_actor, p_event, v_dispute.state, array_to_string(v_rule.allowed_actors, ', ')
      using errcode = 'insufficient_privilege';
  end if;

  perform set_config('app.allow_state_change', 'on', true);

  update public.disputes
  set state = v_rule.to_state,
      state_changed_at = now()
  where id = p_dispute_id
  returning * into v_dispute;

  perform set_config('app.allow_state_change', '', true);

  insert into public.dispute_events
    (dispute_id, from_state, event, to_state, actor, actor_user_id)
  values
    (p_dispute_id, v_rule.from_state, p_event, v_rule.to_state, p_actor, auth.uid());

  return v_dispute;
end;
$$;

create or replace function public.apply_dispute_event(
  p_dispute_id uuid,
  p_event      public.dispute_event
)
returns public.disputes
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_actor public.actor_role;
begin
  v_actor := app.dispute_actor(p_dispute_id);
  if v_actor is null then
    raise exception 'caller is not a party to dispute %', p_dispute_id
      using errcode = 'insufficient_privilege';
  end if;
  return app.apply_dispute_event_as(p_dispute_id, p_event, v_actor);
end;
$$;

revoke all on function public.apply_dispute_event(uuid, public.dispute_event) from public;
grant execute on function public.apply_dispute_event(uuid, public.dispute_event) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- accept_resolution_proposal
--
-- The one entry point a party uses to accept. It records the acceptance, and
-- closes the dispute only when both roles have accepted the SAME proposal.
-- Closing the dispute also resolves the parent contract, as `system`.
-- ---------------------------------------------------------------------------

create or replace function public.accept_resolution_proposal(p_proposal_id uuid)
returns public.disputes
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_dispute_id uuid;
  v_txn_id     uuid;
  v_actor      public.actor_role;
  v_roles      integer;
  v_dispute    public.disputes;
begin
  select p.dispute_id, d.transaction_id
    into v_dispute_id, v_txn_id
  from public.resolution_proposals p
  join public.disputes d on d.id = p.dispute_id
  where p.id = p_proposal_id;

  if v_dispute_id is null then
    raise exception 'proposal % not found', p_proposal_id using errcode = 'no_data_found';
  end if;

  v_actor := app.dispute_actor(v_dispute_id);
  if v_actor is null or v_actor = 'system' then
    raise exception 'only a party to the dispute may accept a proposal'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent by primary key: a retried request changes nothing.
  insert into public.dispute_acceptances (proposal_id, role, user_id)
  values (p_proposal_id, v_actor::text::public.party_role, auth.uid())
  on conflict (proposal_id, role) do nothing;

  select count(distinct role) into v_roles
  from public.dispute_acceptances
  where proposal_id = p_proposal_id;

  if v_roles < 2 then
    select * into v_dispute from public.disputes where id = v_dispute_id;
    return v_dispute;
  end if;

  v_dispute := app.apply_dispute_event_as(v_dispute_id, 'accept_proposal', 'system');
  perform app.apply_transaction_event_as(v_txn_id, 'resolve_dispute', 'system');

  return v_dispute;
end;
$$;

comment on function public.accept_resolution_proposal is
  'Records one party accepting a proposal. Closes the dispute and resolves the contract only once both parties have accepted the same proposal.';

revoke all on function public.accept_resolution_proposal(uuid) from public;
grant execute on function public.accept_resolution_proposal(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.disputes                    enable row level security;
alter table public.resolution_proposals        enable row level security;
alter table public.resolution_findings         enable row level security;
alter table public.resolution_finding_evidence enable row level security;
alter table public.dispute_acceptances         enable row level security;
alter table public.dispute_events              enable row level security;

create policy disputes_select_party
  on public.disputes for select
  to authenticated
  using (app.is_transaction_party(transaction_id));

create policy disputes_insert_party
  on public.disputes for insert
  to authenticated
  with check (
    opened_by = auth.uid()
    and app.is_transaction_party(transaction_id)
  );

-- Claims stay editable by their author while the case has not yet gone to the
-- model. After that the record is what the model saw.
create policy disputes_update_claims_before_review
  on public.disputes for update
  to authenticated
  using (app.is_transaction_party(transaction_id) and state = 'open')
  with check (app.is_transaction_party(transaction_id) and state = 'open');

create policy resolution_proposals_select_party
  on public.resolution_proposals for select
  to authenticated
  using (app.is_dispute_party(dispute_id));

create policy resolution_findings_select_party
  on public.resolution_findings for select
  to authenticated
  using (
    exists (
      select 1 from public.resolution_proposals p
      where p.id = proposal_id and app.is_dispute_party(p.dispute_id)
    )
  );

create policy resolution_finding_evidence_select_party
  on public.resolution_finding_evidence for select
  to authenticated
  using (
    exists (
      select 1
      from public.resolution_findings f
      join public.resolution_proposals p on p.id = f.proposal_id
      where f.id = finding_id and app.is_dispute_party(p.dispute_id)
    )
  );

create policy dispute_acceptances_select_party
  on public.dispute_acceptances for select
  to authenticated
  using (
    exists (
      select 1 from public.resolution_proposals p
      where p.id = proposal_id and app.is_dispute_party(p.dispute_id)
    )
  );

create policy dispute_events_select_party
  on public.dispute_events for select
  to authenticated
  using (app.is_dispute_party(dispute_id));

-- Proposals, findings, acceptances and events are written only through the
-- SECURITY DEFINER functions above and the server-side AI pipeline. No insert,
-- update or delete policy is granted to clients on any of them.
