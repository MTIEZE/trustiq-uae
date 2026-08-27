-- ---------------------------------------------------------------------------
-- 0014  System functions were reachable with the key that ships in the app
--
-- A Supabase project sets default privileges that hand EXECUTE on every new
-- function in `public` to anon, authenticated and service_role. Migrations
-- here wrote `revoke all ... from public` and then granted service_role,
-- which reads like a lock. It is not: PUBLIC is a different thing from the
-- roles, and the automatic grants to anon and authenticated survived it.
--
-- The schema tests said otherwise, and were wrong. A bare Postgres container
-- has no such default privileges, so the revoke removed a grant nobody had
-- and every assertion passed. The harness was safer than production, which is
-- the one direction a test bed must never be. 00_supabase_stubs.sql now sets
-- those default privileges too, and the same assertions fail until this
-- migration runs.
--
-- What that meant in the deployed project, measured rather than reasoned
-- about: calling record_manual_verification over PostgREST with nothing but
-- the publishable key reached the inside of the function. The guard there was
-- `auth.uid() is not null`, which asks "is this a signed-in user?" — and an
-- anonymous caller is not one. Anyone holding the key that ships inside the
-- mobile app could have marked any profile identity-verified.
--
-- Two fixes, because either alone leaves something standing.
--
-- The grants, so the call never routes. And a guard that names who may pass
-- instead of naming one kind of caller who may not, since that is the shape
-- of the mistake: a denylist that had never heard of anon.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Who counts as the server
-- ---------------------------------------------------------------------------

create or replace function app.assert_system_caller(p_what text)
returns void
language plpgsql
stable
as $$
declare
  v_role text;
begin
  -- PostgREST puts the key's role in the request claims. service_role passes;
  -- anon and authenticated are refused by name rather than by absence.
  v_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    ''
  );

  -- An empty role is a direct database connection: migrations, the SQL editor,
  -- psql. Allowed deliberately. Anyone with one of those already owns the
  -- database and does not need a function to get their way.
  if v_role <> '' and v_role <> 'service_role' then
    raise exception '% is a system action and the % role may not perform it', p_what, v_role
      using errcode = 'insufficient_privilege';
  end if;

  -- And no user session, whatever the role claim says.
  if auth.uid() is not null then
    raise exception '% is a system action and cannot be called with a user session', p_what
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_system_caller is
  'Refuses any caller that is not the server. Names who may pass rather than who may not: the hole this replaced was an anon caller slipping through a check for signed-in users.';

-- ---------------------------------------------------------------------------
-- The grants
--
-- anon loses everything. No RPC in this schema has an anonymous caller: sign-up
-- and sign-in go through GoTrue, not through here.
--
-- authenticated keeps only what a signed-in person actually calls. A reviewer
-- is a signed-in person, so claim_dispute and issue_human_resolution stay;
-- both check app.is_reviewer() inside.
-- ---------------------------------------------------------------------------

do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
    -- Extension members are not ours. A real project installs pgcrypto into
    -- `extensions`; a bare container puts it in `public`, and revoking its
    -- grants would be fighting the platform over functions we never wrote.
    and not exists (
      select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
    )
  loop
    execute format('revoke all on function %s from anon', v_fn.sig);
  end loop;
end
$$;

revoke all on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb) from authenticated;
revoke all on function public.record_manual_verification(uuid, text) from authenticated;
revoke all on function public.revoke_verification(uuid, text) from authenticated;

-- Supabase installs functions of its own in `public` (rls_auto_enable, behind
-- the ensure_rls event trigger). They are not named here, because a migration
-- must run on a database that does not have them yet. The loop above reaches
-- whatever is present.

-- ---------------------------------------------------------------------------
-- The guards
--
-- Re-emitted in full rather than patched, because a function body is replaced
-- whole. The bodies below are the ones from 0009 and 0013 with the guard
-- swapped; nothing else changes.
-- ---------------------------------------------------------------------------

create or replace function public.record_manual_verification(
  p_user_id uuid,
  p_note    text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_at timestamptz := now();
begin
  perform app.assert_system_caller('verification');

  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'no profile for %', p_user_id using errcode = 'no_data_found';
  end if;

  insert into app.identity_checks (user_id, outcome, note)
  values (p_user_id, 'verified', p_note);

  update public.profiles
  set identity_verified_at = v_at,
      identity_provider    = 'manual_review'
  where id = p_user_id;

  return v_at;
end;
$$;

create or replace function public.revoke_verification(
  p_user_id uuid,
  p_note    text
)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('verification');

  insert into app.identity_checks (user_id, outcome, note)
  values (p_user_id, 'revoked', p_note);

  update public.profiles
  set identity_verified_at = null,
      identity_provider    = null
  where id = p_user_id;
end;
$$;

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
  -- Nobody holding a client key should be able to author a proposal about
  -- somebody's money, whatever the state machine happens to say.
  perform app.assert_system_caller('issue_ai_proposal');

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

-- CREATE OR REPLACE keeps an existing function's grants rather than resetting
-- them, so this should be a no-op. It runs anyway: the cost is nothing and the
-- alternative is trusting a detail of Postgres that the rest of this migration
-- exists because we got wrong once already.
do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
    -- Extension members are not ours. A real project installs pgcrypto into
    -- `extensions`; a bare container puts it in `public`, and revoking its
    -- grants would be fighting the platform over functions we never wrote.
    and not exists (
      select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
    )
  loop
    execute format('revoke all on function %s from anon', v_fn.sig);
  end loop;
end
$$;

revoke all on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb) from authenticated;
revoke all on function public.record_manual_verification(uuid, text) from authenticated;
revoke all on function public.revoke_verification(uuid, text) from authenticated;

grant execute on function public.issue_ai_proposal(
  uuid, public.resolution_decision, text, bigint, bigint, bigint,
  numeric, text, timestamptz, jsonb) to service_role;
grant execute on function public.record_manual_verification(uuid, text) to service_role;
grant execute on function public.revoke_verification(uuid, text) to service_role;
