-- ---------------------------------------------------------------------------
-- A proposal now records the model call that produced it.
--
-- `ai_call_log` was given a `proposal_id` column in 0006, documented as "set
-- when the call produced a proposal that passed validation and was stored".
-- Nothing ever set it. It could not: the server writes the audit row *before*
-- attempting the store, deliberately, so that a run is recorded even when the
-- store fails, and 0006 made the table append-only with a trigger that refuses
-- every UPDATE. The column was unreachable by construction, and on the live
-- project every row has it null, including the one accepted run of 30 August.
--
-- So the pointer goes the other way. A proposal is written once, in one
-- transaction, and it knows which run made it. A run may produce no proposal,
-- which is most of them so far, and that shape is now what the schema says.
--
-- The link is only obtainable at insert time, because `resolution_proposals`
-- is immutable too. Existing rows therefore stay unlinked. Guessing which of
-- four proposals belongs to which of five audit rows, on a table whose value
-- is that it cannot be rewritten, is not a backfill, it is a fabrication.
-- ---------------------------------------------------------------------------

alter table public.resolution_proposals
  add column ai_call_id bigint;

-- Deferred, because deleting a dispute cascades into both tables at once and
-- the order between siblings is not defined. Checked at commit, by which time
-- either both rows are gone or neither is.
alter table public.resolution_proposals
  add constraint resolution_proposals_ai_call_fkey
  foreign key (ai_call_id) references public.ai_call_log (id)
  deferrable initially deferred;

comment on column public.resolution_proposals.ai_call_id is
  'The ai_call_log row for the run that produced this proposal. Null on human proposals, and on AI proposals issued before migration 0027.';

-- NOT VALID: enforced from here on, and the four rows that predate this are
-- left alone rather than being invented.
alter table public.resolution_proposals
  add constraint proposal_ai_call_matches_source check (
    (source = 'human' and ai_call_id is null)
    or (source = 'ai' and ai_call_id is not null)
  ) not valid;

create index resolution_proposals_ai_call_idx
  on public.resolution_proposals (ai_call_id);

-- The column that could never be written.
alter table public.ai_call_log drop column proposal_id;

-- ---------------------------------------------------------------------------
-- issue_ai_proposal, taking the run it belongs to.
--
-- Dropped and recreated rather than replaced: the argument list changes, and
-- two overloads in `public` is an ambiguity PostgREST resolves by guessing.
-- ---------------------------------------------------------------------------

drop function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb
);

create function public.issue_ai_proposal(
  p_dispute_id           uuid,
  p_decision             public.resolution_decision,
  p_summary              text,
  p_disputed_amount_fils bigint,
  p_seller_amount_fils   bigint,
  p_buyer_amount_fils    bigint,
  p_confidence           numeric,
  p_model_id             text,
  p_issued_at            timestamptz,
  -- [{ "statement": "...", "evidenceIds": ["uuid", ...] }, ...]
  p_findings             jsonb,
  -- The ai_call_log row written before this call was attempted. Required: an
  -- AI proposal that cannot name its run is the gap this migration closes.
  p_ai_call_id           bigint
)
returns uuid
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_proposal_id uuid;
  v_finding     jsonb;
  v_finding_id  uuid;
  v_position    integer := 0;
begin
  -- A system action, and only a system action. `apply_dispute_event` derives
  -- its actor from auth.uid() and would resolve a signed-in party to 'buyer' or
  -- 'seller', neither of which may fire `issue_proposal`. Rather than rely on
  -- that indirection, refuse an authenticated caller outright: nobody holding a
  -- user session should be able to author a proposal about their own money,
  -- whatever the state machine happens to say.
  if auth.uid() is not null then
    raise exception 'issue_ai_proposal is a system action and cannot be called with a user session'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.disputes d where d.id = p_dispute_id) then
    raise exception 'dispute % not found', p_dispute_id
      using errcode = 'no_data_found';
  end if;

  if p_ai_call_id is null then
    raise exception 'a proposal must name the run that produced it'
      using errcode = 'check_violation';
  end if;

  if p_findings is null
     or jsonb_typeof(p_findings) <> 'array'
     or jsonb_array_length(p_findings) = 0
  then
    raise exception 'a proposal must carry at least one finding'
      using errcode = 'check_violation';
  end if;

  insert into public.resolution_proposals (
    dispute_id, source, decision, summary,
    disputed_amount_fils, seller_amount_fils, buyer_amount_fils,
    confidence, model_id, issued_at, ai_call_id
  )
  values (
    p_dispute_id, 'ai', p_decision, p_summary,
    p_disputed_amount_fils, p_seller_amount_fils, p_buyer_amount_fils,
    p_confidence, p_model_id, coalesce(p_issued_at, now()), p_ai_call_id
  )
  returning id into v_proposal_id;

  for v_finding in select * from jsonb_array_elements(p_findings)
  loop
    insert into public.resolution_findings (proposal_id, position, statement)
    values (v_proposal_id, v_position, v_finding ->> 'statement')
    returning id into v_finding_id;

    -- DISTINCT because the same id cited twice in one statement is noise, not
    -- a reason to throw the proposal away on a primary key violation.
    insert into public.resolution_finding_evidence (finding_id, evidence_id)
    select distinct v_finding_id, (value #>> '{}')::uuid
    from jsonb_array_elements(coalesce(v_finding -> 'evidenceIds', '[]'::jsonb));

    v_position := v_position + 1;
  end loop;

  -- Last, so a proposal that could not be written completely never becomes
  -- visible to the parties. An ungrounded finding fails at commit and takes
  -- this transition down with it.
  perform app.apply_dispute_event_as(p_dispute_id, 'issue_proposal', 'system');

  return v_proposal_id;
end;
$$;

comment on function public.issue_ai_proposal is
  'Stores an AI proposal with its findings, citations and the run that produced it, then publishes it, all in one transaction. Service role only.';

revoke all on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb, bigint) from public;

-- Not granted to `authenticated`. A party must never be able to author the
-- proposal that decides their own dispute. Stated against the new signature
-- because the revokes in 0009 and 0014 named the old one, which no longer
-- exists: a grant is attached to a signature, not to a name.
revoke all on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb, bigint) from anon, authenticated;

grant execute on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb, bigint) to service_role;
