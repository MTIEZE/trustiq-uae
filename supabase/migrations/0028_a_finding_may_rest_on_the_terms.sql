-- ---------------------------------------------------------------------------
-- A finding may rest on the agreed terms, not only on a filed document.
--
-- Ten live runs on 1 September 2026 refused three proposals for an ungrounded
-- finding, and reading the stored responses back showed the model had invented
-- nothing. It had written sentences like "the agreed terms contain no design
-- specification beyond the word modern" and "the buyer submitted no evidence
-- of the delivered site". Both true, both the most useful lines in their case,
-- and both uncitable: the terms go into the prompt as a quoted block with no
-- id, an absence has nothing to point at, and every finding had to cite ids
-- drawn from the evidence list. The rate followed the evidence count exactly —
-- with two documents 1 of 9 runs was refused, with exactly one document 3 of 3.
--
-- So the pipeline escalated those cases for the wrong reason and threw away
-- sound reasoning on the way.
--
-- What has not changed is that a finding must rest on something. The anchor set
-- gains one member, and it is the strongest thing in the file: both parties
-- accepted the terms and neither can change them afterwards.
-- ---------------------------------------------------------------------------

alter table public.resolution_findings
  add column cites_terms boolean not null default false;

comment on column public.resolution_findings.cites_terms is
  'Whether this statement rests on the agreed terms themselves rather than on a filed document.';

-- ---------------------------------------------------------------------------
-- The grounding check, with the wider anchor.
-- ---------------------------------------------------------------------------

create or replace function app.check_finding_is_grounded()
returns trigger
language plpgsql
as $$
declare
  v_count integer;
begin
  -- The agreement is part of the record and neither party can rewrite it, so a
  -- statement resting on it is grounded without a document behind it.
  if new.cites_terms then
    return null;
  end if;

  select count(*) into v_count
  from public.resolution_finding_evidence fe
  where fe.finding_id = new.id;

  if v_count = 0 then
    raise exception
      'finding % rests on neither evidence nor the agreed terms; a statement about someone''s money must be grounded',
      new.id
      using errcode = 'check_violation';
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- issue_ai_proposal, reading the flag out of each finding.
--
-- The argument list does not change: findings arrive as jsonb, so this is a
-- body change and the grants stay attached to the signature they were made on.
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
  -- [{ "statement": "...", "evidenceIds": ["uuid", ...], "citesTerms": bool }, ...]
  p_findings             jsonb,
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
    insert into public.resolution_findings (proposal_id, position, statement, cites_terms)
    values (
      v_proposal_id,
      v_position,
      v_finding ->> 'statement',
      -- Absent reads as false, which is the safe direction: a finding that
      -- forgot to say it rests on the terms is then held to the document rule
      -- rather than waved through.
      coalesce((v_finding ->> 'citesTerms')::boolean, false)
    )
    returning id into v_finding_id;

    insert into public.resolution_finding_evidence (finding_id, evidence_id)
    select distinct v_finding_id, (value #>> '{}')::uuid
    from jsonb_array_elements(coalesce(v_finding -> 'evidenceIds', '[]'::jsonb));

    v_position := v_position + 1;
  end loop;

  perform app.apply_dispute_event_as(p_dispute_id, 'issue_proposal', 'system');

  return v_proposal_id;
end;
$$;
