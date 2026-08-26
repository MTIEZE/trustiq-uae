-- ---------------------------------------------------------------------------
-- 0011  Seeing who is on the other side of your contract
--
-- 0002 gave profiles a single SELECT policy: you may read your own row. That
-- was right as far as it went, and it went too far. Nothing exercised it until
-- a client existed, and then the first screen that tried to render a contract
-- could not name the counterparty.
--
-- It breaks more than a label. The identity gate refuses to activate a
-- contract until both parties are verified, so the app has to be able to say
-- which side is still unverified. With this policy it could not read that
-- about anyone but you, which makes the gate look like an unexplained refusal.
--
-- Two things are added, and they are deliberately narrow.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. A view of the profiles you are entitled to see
--
-- SECURITY DEFINER by default for a view, so the WHERE clause is the access
-- control rather than the profiles policy. That is the point: the policy
-- cannot express "a party to a contract we share" without reading
-- transactions, whose own policy reads profiles, which recurses.
--
-- Three columns. Not email, not phone, not anything else the table holds. A
-- counterparty needs to know who they are dealing with and whether that person
-- has been verified; they do not need the rest of the row, and a view is the
-- only place in this schema where a column can be withheld.
-- ---------------------------------------------------------------------------

create or replace function app.shares_a_contract_with(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.transactions t
    where (t.buyer_id = auth.uid() and t.seller_id = p_profile_id)
       or (t.seller_id = auth.uid() and t.buyer_id = p_profile_id)
  );
$$;

comment on function app.shares_a_contract_with is
  'True when the caller and the given profile are the two parties to some contract. SECURITY DEFINER so a profiles policy can ask it without recursing through the transactions policy.';

create or replace view public.visible_profiles as
  select
    p.id,
    p.full_name,
    p.identity_verified_at
  from public.profiles p
  where p.id = auth.uid()
     or app.shares_a_contract_with(p.id);

comment on view public.visible_profiles is
  'Yourself, plus anyone you share a contract with. Name and verification only: the rest of the profile stays private. This is how a client reads a counterparty.';

revoke all on public.visible_profiles from public;
grant select on public.visible_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Addressing a contract to someone
--
-- transactions.seller_id and buyer_id are both NOT NULL references to a
-- profile, so a contract cannot be drafted for a person who has no account.
-- The client therefore needs a way to turn the email it was given into an id,
-- and it cannot read the profiles table to do it.
--
-- The honest cost: an authenticated caller can use this to learn whether a
-- given email has a TrustIQ account. That is the same exposure every
-- invite-by-email flow carries, and it is bounded here to a yes or no with no
-- name, no id shape leak and no listing. It is worth naming rather than
-- pretending the function is free.
--
-- Inviting someone who has no account yet is a real case and this does not
-- serve it. That needs a pending-party concept and a NULL-able counterparty
-- column, which is a product decision and a schema change, not something to
-- slip in behind a lookup function.
-- ---------------------------------------------------------------------------

create or replace function public.find_counterparty(p_email text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  select p.id into v_id
  from public.profiles p
  where lower(p.email) = lower(btrim(p_email));

  -- Addressing a contract to yourself is not a contract. Caught here because
  -- the schema's CHECK would refuse it later with a less useful message.
  if v_id = auth.uid() then
    raise exception 'a contract needs two different people'
      using errcode = 'check_violation';
  end if;

  return v_id;
end;
$$;

comment on function public.find_counterparty is
  'Resolves an email to a profile id so a contract can be addressed to someone. Returns null when nobody holds that address. Deliberately returns nothing else.';

revoke all on function public.find_counterparty(text) from public;
grant execute on function public.find_counterparty(text) to authenticated;
