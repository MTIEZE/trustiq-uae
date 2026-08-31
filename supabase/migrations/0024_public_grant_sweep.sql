-- ---------------------------------------------------------------------------
-- The sweep in 0014, finished.
--
-- 0014 revoked EXECUTE from `anon` on every function in `public`, and the test
-- suite has asserted ever since that nothing there is callable with the key
-- that ships inside the app. That assertion passes. It was also, in production,
-- untrue.
--
-- `rls_auto_enable`, which Supabase installs itself behind its ensure_rls event
-- trigger, was reachable by anon on the live project. Its ACL read
-- `{=X/postgres,...}`, and the leading `=X` is a grant to PUBLIC. 0014 said
-- `revoke ... from anon`, which does nothing about a privilege held through
-- PUBLIC, so the loop passed straight over it. The schema tests never saw it
-- because the harness builds a database from these migrations and Supabase's
-- own objects are not in them.
--
-- The exposure was nil: Postgres refuses to call an event trigger function
-- directly. The guarantee was still false, and a guarantee that is false
-- somewhere nobody looks is the kind that is discovered by somebody else.
--
-- Two things follow. The sweep below takes PUBLIC as well, and there is now a
-- function that reports what is reachable so the live project can be asked the
-- same question the tests ask, rather than trusting that the two agree.
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
      -- Extension members are not ours to touch, same as in 0014.
      and not exists (
        select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
      )
  loop
    -- PUBLIC first. Nothing in this project ever grants through PUBLIC: every
    -- intended grant is written out to `authenticated` or `service_role`, so
    -- taking it back can only remove something nobody meant to give.
    execute format('revoke all on function %s from public', v_fn.sig);
    execute format('revoke all on function %s from anon', v_fn.sig);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Asking the live project the question the tests ask
--
-- The schema suite runs against a database built from this folder. Production
-- also has whatever the platform put there, and gets whatever the platform
-- adds later. This is how the two can be compared instead of assumed equal.
-- ---------------------------------------------------------------------------

create or replace function public.client_reachable_functions()
returns table (signature text, by_anon boolean, by_authenticated boolean)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_system_caller('auditing function grants');

  return query
  select
    p.oid::regprocedure::text,
    has_function_privilege('anon', p.oid, 'EXECUTE'),
    has_function_privilege('authenticated', p.oid, 'EXECUTE')
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (
      select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE')
  order by 1;
end;
$$;

comment on function public.client_reachable_functions is
  'Anything in public that the key shipping inside the app can call. Should always be empty; scripts/run-schedule.mjs fails the daily job if it is not.';

revoke all on function public.client_reachable_functions() from public, anon, authenticated;
grant execute on function public.client_reachable_functions() to service_role;
