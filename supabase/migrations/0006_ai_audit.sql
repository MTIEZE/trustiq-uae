-- ---------------------------------------------------------------------------
-- 0006  AI call audit trail
--
-- Every call to the resolution model is recorded in full: the exact model, the
-- payload sent, what came back, how long it took, and what the validator did
-- with it. Without this there is no way to answer "why did the system propose
-- that?" months later, which is the first question in any contested case.
--
-- Rejected outputs are recorded too. A model that fails validation often is a
-- signal, and deleting the failures hides it.
-- ---------------------------------------------------------------------------

create table public.ai_call_log (
  id                 bigint generated always as identity primary key,
  dispute_id         uuid not null references public.disputes (id) on delete cascade,

  -- Set when the call produced a proposal that passed validation and was stored.
  proposal_id        uuid references public.resolution_proposals (id) on delete set null,

  model_id           text not null check (length(btrim(model_id)) > 0),
  prompt_version     text not null check (length(btrim(prompt_version)) > 0),

  request_payload    jsonb not null,
  response_payload   jsonb,

  confidence         numeric(4, 3) check (confidence >= 0 and confidence <= 1),

  -- 'accepted', or the ProposalRejectionCode from
  -- packages/core/src/resolution.ts when validation refused the output.
  validation_outcome text not null check (length(btrim(validation_outcome)) > 0),
  escalation_reasons text[] not null default '{}',

  latency_ms         integer check (latency_ms >= 0),
  error_message      text,

  created_at         timestamptz not null default now()
);

comment on table public.ai_call_log is
  'Full audit trail of resolution model calls, including outputs that failed validation. Append-only, service role only.';

create index ai_call_log_dispute_idx  on public.ai_call_log (dispute_id, created_at desc);
create index ai_call_log_outcome_idx  on public.ai_call_log (validation_outcome, created_at desc);

create trigger ai_call_log_immutable
  before update or delete on public.ai_call_log
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- RLS
--
-- No policy is created for `authenticated`, so with RLS enabled the table is
-- invisible to clients: prompts and raw model output are internal. Parties see
-- the resolution through resolution_proposals and resolution_findings, which is
-- the reviewed, validated view of the same thing.
--
-- If a data subject access request later requires exposing this, add a policy
-- deliberately rather than leaving one open by default.
-- ---------------------------------------------------------------------------

alter table public.ai_call_log enable row level security;

-- ---------------------------------------------------------------------------
-- Final grants
--
-- PostgREST exposes `public`. Nothing in `app` should be reachable from a
-- client, so lock the internal tables down explicitly rather than relying on
-- them simply not being requested.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema app from anon, authenticated;

grant execute on function app.is_transaction_party(uuid)        to authenticated;
grant execute on function app.transaction_is_draft(uuid)        to authenticated;
grant execute on function app.transaction_accepts_evidence(uuid) to authenticated;
grant execute on function app.is_dispute_party(uuid)            to authenticated;
grant execute on function app.shares_transaction_with(uuid)     to authenticated;
