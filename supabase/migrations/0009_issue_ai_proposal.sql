-- ---------------------------------------------------------------------------
-- 0009  Write a whole proposal in one transaction
--
-- `resolution_findings_must_be_grounded` is a DEFERRABLE INITIALLY DEFERRED
-- constraint trigger: it runs at commit, so a finding row and its citations can
-- be inserted in either order as long as they share a transaction.
--
-- The server did not share one. It wrote the proposal, then each finding, then
-- each finding's citations, as separate PostgREST requests. Every request is
-- its own transaction, so the deferred check ran at the end of the finding's
-- own insert, before any citation existed, and refused every proposal:
--
--   finding <id> cites no evidence; a statement about someone's money must be
--   grounded (23514)
--
-- The SQL suite never caught it because psql runs a whole test file inside one
-- transaction, which is exactly the condition the server could not provide.
-- Running the pipeline against the live project is what exposed it.
--
-- Worse than the failure itself: the proposal row landed and the findings did
-- not, so the dispute escalated while an orphan proposal sat in the table. The
-- adapter's comment claimed "the proposal never lands half-built". Over
-- PostgREST that was not true, and it could not be made true from the client
-- side, because PostgREST offers no way to span a transaction across requests.
--
-- So the whole write moves into the database, where a transaction already
-- exists. One call, one transaction, and the deferred trigger finally does the
-- job it was written for.
-- ---------------------------------------------------------------------------

create or replace function public.issue_ai_proposal(
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
  p_findings             jsonb
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
    confidence, model_id, issued_at
  )
  values (
    p_dispute_id, 'ai', p_decision, p_summary,
    p_disputed_amount_fils, p_seller_amount_fils, p_buyer_amount_fils,
    p_confidence, p_model_id, coalesce(p_issued_at, now())
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
  'Stores an AI proposal with its findings and citations, then publishes it, all in one transaction. Service role only.';

revoke all on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint, numeric, text, timestamptz, jsonb
) from public;

-- Not granted to `authenticated`. A party must never be able to author the
-- proposal that decides their own dispute.
grant execute on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint, numeric, text, timestamptz, jsonb
) to service_role;
