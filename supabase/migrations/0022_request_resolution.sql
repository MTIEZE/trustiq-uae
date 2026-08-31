-- ---------------------------------------------------------------------------
-- Who may ask the model to look at a dispute.
--
-- One function, used twice, on purpose. The app calls it to decide what to put
-- on screen, and the edge function calls it with the same caller's token as the
-- gate before spending anything. A rule written once cannot drift between the
-- screen that shows it and the server that enforces it, and a screen-only
-- restriction is not a restriction: it is a suggestion to anybody holding curl.
--
-- ---------------------------------------------------------------------------
-- On how much this actually stops, said plainly
--
-- Today, not much, and the reason is a good one. A dispute can only be opened
-- on a contract that is `active` or `delivered`, and reaching `active` requires
-- an `accept`, which 0003 refuses unless both parties are verified. So everyone
-- who can be in a dispute was verified at the moment the contract became
-- binding.
--
-- What this catches is the case where that stopped being true. `revoke_
-- verification` sets identity_verified_at back to null, which is what happens
-- when a check turns out to have been wrong or an account turns out to be
-- somebody else's. Without this, that person could still spend a model call on
-- a contract they entered under a verification that has since been withdrawn,
-- and hold the resulting document up as a finding about them.
--
-- Narrow, then. Written anyway, because the alternative is a rule that exists
-- only in an app somebody can decompile, and because the cost of the check is
-- one row read against the cost of an Opus call.
-- ---------------------------------------------------------------------------

create or replace function public.may_request_resolution(p_dispute_id uuid)
returns table (allowed boolean, reason text)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me       uuid := auth.uid();
  v_state    text;
  v_is_party boolean;
begin
  if v_me is null then
    raise exception 'asking for a resolution needs a signed-in caller'
      using errcode = 'insufficient_privilege';
  end if;

  -- Reads past RLS because it is `security definer`, so being a party is
  -- checked here rather than assumed from the read succeeding.
  select d.state::text,
         exists (
           select 1 from public.transactions t
           where t.id = d.transaction_id and v_me in (t.buyer_id, t.seller_id)
         )
  into v_state, v_is_party
  from public.disputes d
  where d.id = p_dispute_id;

  -- Checked first, and answered the same way whether the dispute is missing or
  -- simply none of theirs. Any other order tells a stranger that a given
  -- dispute exists by refusing them for a more specific reason.
  if v_state is null or not coalesce(v_is_party, false) then
    return query select false, 'not_found'::text;
    return;
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_me and p.identity_verified_at is not null
  ) then
    return query select false, 'not_verified'::text;
    return;
  end if;

  -- The analysis runs once. Anything past `open` has already been through it,
  -- or is with a human, or is finished. Returned as the state itself so the
  -- screen can say which, rather than as a single unhelpful "no".
  if v_state <> 'open' then
    return query select false, v_state;
    return;
  end if;

  return query select true, null::text;
end;
$$;

comment on function public.may_request_resolution is
  'Whether the caller may send this dispute to the model, and if not, why. Read by the app to decide what to show and by the edge function as the gate.';

revoke all on function public.may_request_resolution(uuid) from public, anon;
grant execute on function public.may_request_resolution(uuid) to authenticated;
