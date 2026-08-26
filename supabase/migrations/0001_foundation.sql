-- ---------------------------------------------------------------------------
-- 0001  Foundation: schema, enums, money guards, shared helpers
--
-- The enums below mirror packages/core/src/types.ts exactly. If you add a state
-- or an event on one side, add it on the other in the same change. The schema
-- test suite fails if the two drift.
-- ---------------------------------------------------------------------------

create extension if not exists pgcrypto;

-- Internals live in `app`, which is NOT exposed through PostgREST. Anything a
-- client is allowed to call is either a table in `public` behind RLS, or an
-- explicitly granted function.
create schema if not exists app;
revoke all on schema app from public;

-- ---------------------------------------------------------------------------
-- Roles and actors
-- ---------------------------------------------------------------------------

create type public.party_role as enum ('buyer', 'seller');

-- `system` covers timers, the AI pipeline and reconciliation. It is never a
-- user. In practice a request has actor `system` only when it arrives without
-- an authenticated user, which means the service role.
create type public.actor_role as enum ('buyer', 'seller', 'system');

-- ---------------------------------------------------------------------------
-- Transaction lifecycle
-- ---------------------------------------------------------------------------

create type public.transaction_state as enum (
  'draft',
  'pending_acceptance',
  'active',
  'delivered',
  'completed',
  'disputed',
  'resolved',
  'declined',
  'cancelled',
  'expired'
  -- ESCROW-V2: 'funding_pending' and 'funds_held' slot in after
  -- 'pending_acceptance' once a licensed partner holds funds.
);

create type public.transaction_event as enum (
  'submit',
  'withdraw',
  'accept',
  'decline',
  'expire',
  'mark_delivered',
  'request_revision',
  'confirm_delivery',
  'open_dispute',
  'resolve_dispute',
  'cancel_by_agreement'
);

-- ---------------------------------------------------------------------------
-- Dispute lifecycle
-- ---------------------------------------------------------------------------

create type public.dispute_state as enum (
  'open',
  'ai_review',
  'proposal_issued',
  'accepted',
  'escalated',
  'human_review',
  'resolved_by_human',
  'withdrawn'
);

create type public.dispute_event as enum (
  'submit_for_ai',
  'issue_proposal',
  'accept_proposal',
  'reject_proposal',
  'escalate',
  'assign_reviewer',
  'issue_human_resolution',
  'withdraw_dispute'
);

create type public.resolution_decision as enum (
  'release_to_seller',
  'refund_to_buyer',
  'split'
);

-- ---------------------------------------------------------------------------
-- Money
--
-- Every amount is a bigint count of fils (1 AED = 100 fils). There is no
-- numeric and no float anywhere in this schema, on purpose. MAX_FILS matches
-- the ceiling enforced in packages/core/src/money.ts.
-- ---------------------------------------------------------------------------

create domain public.fils as bigint
  constraint fils_within_range check (value between -9223372036854 and 9223372036854);

comment on domain public.fils is
  'An amount in fils, the minor unit of the UAE dirham. 1 AED = 100 fils. Never store money as numeric or float.';

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function app.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Blocks UPDATE and DELETE outright, including for the service role, which
-- bypasses RLS. Used on evidence and on the audit logs: those rows are
-- append-only or the audit trail is worthless in a dispute.
create or replace function app.forbid_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% rows are append-only and cannot be % (table %)',
    tg_table_name, lower(tg_op), tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

grant usage on schema app to authenticated, anon, service_role;
