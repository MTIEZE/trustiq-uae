-- ---------------------------------------------------------------------------
-- 0008  Tell a missing dispute apart from an unauthorised caller
--
-- apply_dispute_event answered "caller is not a party to dispute X" for a
-- dispute that does not exist. app.dispute_actor selects through a join, and a
-- missing dispute means no rows, which means NULL, which the caller reads as
-- "not a party".
--
-- Nothing was broken by this: events on disputes that exist behave correctly,
-- and both answers refuse the call. But the two need different fixes, and a
-- log full of "not a party" for what is really a bad identifier sends whoever
-- reads it looking in the wrong place. apply_transaction_event already gets
-- this right; this brings the dispute side in line.
-- ---------------------------------------------------------------------------

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
  -- Existence first, so a bad id is reported as a bad id.
  if not exists (select 1 from public.disputes d where d.id = p_dispute_id) then
    raise exception 'dispute % not found', p_dispute_id
      using errcode = 'no_data_found';
  end if;

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
