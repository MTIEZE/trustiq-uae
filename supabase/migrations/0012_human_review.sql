-- ---------------------------------------------------------------------------
-- 0012  The human the product promises
--
-- "The AI proposes, it does not rule." One refusal from either party sends the
-- case to a human. 0005 wrote the states for that on day one:
--
--   escalated  --assign_reviewer-->  human_review
--   human_review  --issue_human_resolution-->  resolved_by_human
--
-- and then nothing else was built. A dispute reaching `escalated` stopped
-- there permanently. There was no reviewer, no way to see the queue, and no
-- way to record a decision. The central claim of the product was true in the
-- state table and false everywhere else.
--
-- This is the rest of it.
--
-- Three decisions worth stating, because each one could reasonably have gone
-- the other way.
--
-- **A reviewer is not a party, and holds no service-role key.** Staff tooling
-- that runs on a key which bypasses row level security means every reviewer
-- can read every contract in the system. A reviewer signs in as themselves and
-- row level security decides what they see, exactly as it does for a buyer.
--
-- **A reviewer sees a case only from the moment it needs them.** Never while
-- the parties are still working it out, and never a case they resolved between
-- themselves. A dispute the two sides settled is none of a reviewer's business.
--
-- **A reviewer does not learn who the parties are.** They read the roles, the
-- claims, the evidence and the history. Not names, not emails. A decision
-- about 500 AED should not turn on whose name is on the contract, and the
-- cheapest way to guarantee that is to withhold it.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Who reviews
--
-- In `app`, so no client role can read the list or add themselves to it. Rows
-- are written with the service role, which is a deliberate friction: making
-- someone a reviewer is an administrative act, not a self-service one.
-- ---------------------------------------------------------------------------

create table app.reviewers (
  user_id  uuid primary key references public.profiles (id) on delete restrict,
  added_at timestamptz not null default now(),
  note     text
);

comment on table app.reviewers is
  'People who may pick up escalated disputes. Service role only: nobody can add themselves.';

create or replace function app.is_reviewer()
returns boolean
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select auth.uid() is not null
     and exists (select 1 from app.reviewers r where r.user_id = auth.uid());
$$;

/* The states in which a case is a reviewer's business, and no others. */
create or replace function app.reviewable_dispute(p_dispute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select app.is_reviewer()
     and exists (
       select 1 from public.disputes d
       where d.id = p_dispute_id
         and d.state in ('escalated', 'human_review', 'resolved_by_human')
     );
$$;

-- ---------------------------------------------------------------------------
-- 2. Who picked the case up
-- ---------------------------------------------------------------------------

alter table public.disputes
  add column reviewer_id uuid references public.profiles (id) on delete restrict,
  add column claimed_at  timestamptz;

comment on column public.disputes.reviewer_id is
  'The reviewer who claimed this case. Set by claim_dispute and never by a client.';

-- ---------------------------------------------------------------------------
-- 3. What a reviewer can read
--
-- SELECT only, everywhere. A reviewer changes a case through the two functions
-- below and through nothing else, so there is no UPDATE or INSERT policy here
-- for any of these tables.
-- ---------------------------------------------------------------------------

create policy disputes_select_reviewer
  on public.disputes for select
  to authenticated
  using (
    app.is_reviewer()
    and state in ('escalated', 'human_review', 'resolved_by_human')
  );

-- Every reference to the row being tested is written out in full, table name
-- and all. An unqualified column inside these subqueries binds to the
-- subquery's own table when both have it, and `disputes` shares
-- `transaction_id` with three of these tables. `d.transaction_id =
-- transaction_id` reads like a join and compiles to `d.transaction_id =
-- d.transaction_id`, which is always true: the policy would then show a
-- reviewer every row in the table as soon as any case was reviewable. Both
-- shapes were written here first and one of them was caught only because a
-- neighbouring policy failed loudly for the same reason.

create policy transactions_select_reviewer
  on public.transactions for select
  to authenticated
  using (
    exists (
      select 1 from public.disputes d
      where d.transaction_id = public.transactions.id
        and app.reviewable_dispute(d.id)
    )
  );

create policy evidence_select_reviewer
  on public.evidence for select
  to authenticated
  using (
    exists (
      select 1 from public.disputes d
      where d.transaction_id = public.evidence.transaction_id
        and app.reviewable_dispute(d.id)
    )
  );

create policy transaction_events_select_reviewer
  on public.transaction_events for select
  to authenticated
  using (
    exists (
      select 1 from public.disputes d
      where d.transaction_id = public.transaction_events.transaction_id
        and app.reviewable_dispute(d.id)
    )
  );

create policy dispute_events_select_reviewer
  on public.dispute_events for select
  to authenticated
  using (app.reviewable_dispute(public.dispute_events.dispute_id));

create policy resolution_proposals_select_reviewer
  on public.resolution_proposals for select
  to authenticated
  using (app.reviewable_dispute(public.resolution_proposals.dispute_id));

create policy resolution_findings_select_reviewer
  on public.resolution_findings for select
  to authenticated
  using (
    exists (
      select 1 from public.resolution_proposals p
      where p.id = public.resolution_findings.proposal_id
        and app.reviewable_dispute(p.dispute_id)
    )
  );

create policy resolution_finding_evidence_select_reviewer
  on public.resolution_finding_evidence for select
  to authenticated
  using (
    exists (
      select 1
      from public.resolution_findings f
      join public.resolution_proposals p on p.id = f.proposal_id
      where f.id = public.resolution_finding_evidence.finding_id
        and app.reviewable_dispute(p.dispute_id)
    )
  );

-- Deliberately absent: a policy on `profiles` and no place in
-- `visible_profiles`. A reviewer reads roles, never names.

-- ---------------------------------------------------------------------------
-- 4. Claiming a case
--
-- One reviewer at a time, so two people cannot quietly work the same dispute
-- and write contradicting decisions. The state machine does most of it: once
-- the case is in `human_review`, `assign_reviewer` is no longer a legal move.
-- ---------------------------------------------------------------------------

create or replace function public.claim_dispute(p_dispute_id uuid)
returns public.disputes
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_dispute public.disputes;
begin
  if not app.is_reviewer() then
    raise exception 'only a reviewer may claim a dispute'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.disputes d where d.id = p_dispute_id) then
    raise exception 'dispute % not found', p_dispute_id using errcode = 'no_data_found';
  end if;

  -- Recorded before the transition, so a case in `human_review` always names
  -- the person holding it.
  update public.disputes
  set reviewer_id = auth.uid(),
      claimed_at  = now()
  where id = p_dispute_id;

  -- `assign_reviewer` is legal only from `escalated`, so a second reviewer
  -- arriving at the same case is refused here by the transition table.
  v_dispute := app.apply_dispute_event_as(p_dispute_id, 'assign_reviewer', 'system');
  return v_dispute;
end;
$$;

comment on function public.claim_dispute is
  'A reviewer picks up an escalated case. Refused once someone else holds it.';

revoke all on function public.claim_dispute(uuid) from public;
grant execute on function public.claim_dispute(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Recording the decision
--
-- One call, one transaction, for the same reason as issue_ai_proposal: the
-- grounding trigger is deferred and only works if a finding and its citations
-- share a transaction. See migration 0009 for what happens otherwise.
--
-- Two ways this differs from the AI path, both deliberate.
--
-- The parties do not accept it. A human reviewer is the escalation, not
-- another proposal to argue with, and `issue_human_resolution` goes straight
-- to `resolved_by_human` in the state table.
--
-- Findings are optional. The model must ground every statement because nobody
-- is accountable for what it writes; a reviewer is named in `reviewer_id` and
-- their summary is their reasoning. Any finding they do write is still
-- grounded, because that trigger applies to every proposal.
-- ---------------------------------------------------------------------------

create or replace function public.issue_human_resolution(
  p_dispute_id         uuid,
  p_decision           public.resolution_decision,
  p_summary            text,
  p_seller_amount_fils bigint,
  p_buyer_amount_fils  bigint,
  -- [{ "statement": "...", "evidenceIds": ["uuid", ...] }, ...], may be empty
  p_findings           jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_dispute     public.disputes;
  v_proposal_id uuid;
  v_finding     jsonb;
  v_finding_id  uuid;
  v_position    integer := 0;
begin
  if not app.is_reviewer() then
    raise exception 'only a reviewer may resolve a dispute'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_dispute from public.disputes where id = p_dispute_id;
  if not found then
    raise exception 'dispute % not found', p_dispute_id using errcode = 'no_data_found';
  end if;

  -- Whoever picked the case up is the one who decides it. Without this, a
  -- second reviewer could write the decision on a case they never claimed and
  -- the record would name the wrong person.
  if v_dispute.reviewer_id is distinct from auth.uid() then
    raise exception 'this case is held by another reviewer'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.resolution_proposals (
    dispute_id, source, decision, summary,
    disputed_amount_fils, seller_amount_fils, buyer_amount_fils,
    confidence, model_id, issued_at
  )
  values (
    p_dispute_id, 'human', p_decision, p_summary,
    v_dispute.disputed_amount_fils, p_seller_amount_fils, p_buyer_amount_fils,
    -- Null on both, and the schema insists: a human decision must not borrow
    -- the model's clothes by carrying a confidence it never computed.
    null, null, now()
  )
  returning id into v_proposal_id;

  for v_finding in select * from jsonb_array_elements(coalesce(p_findings, '[]'::jsonb))
  loop
    insert into public.resolution_findings (proposal_id, position, statement)
    values (v_proposal_id, v_position, v_finding ->> 'statement')
    returning id into v_finding_id;

    insert into public.resolution_finding_evidence (finding_id, evidence_id)
    select distinct v_finding_id, (value #>> '{}')::uuid
    from jsonb_array_elements(coalesce(v_finding -> 'evidenceIds', '[]'::jsonb));

    v_position := v_position + 1;
  end loop;

  perform app.apply_dispute_event_as(p_dispute_id, 'issue_human_resolution', 'system');
  perform app.apply_transaction_event_as(v_dispute.transaction_id, 'resolve_dispute', 'system');

  return v_proposal_id;
end;
$$;

comment on function public.issue_human_resolution is
  'A reviewer decides a case they hold. Writes the resolution, closes the dispute and resolves the contract, in one transaction. Reviewers only.';

revoke all on function public.issue_human_resolution(
  uuid, public.resolution_decision, text, bigint, bigint, jsonb
) from public;

grant execute on function public.issue_human_resolution(
  uuid, public.resolution_decision, text, bigint, bigint, jsonb
) to authenticated, service_role;
