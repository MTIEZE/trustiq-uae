-- ---------------------------------------------------------------------------
-- 0015  Addressing a contract to somebody who has not heard of TrustIQ
--
-- Until now a contract could only name a person who already had an account.
-- For a closed beta where you know all ten people, that is survivable. Past
-- that it is the thing that stops the product spreading, because half of every
-- transaction is somebody who has never heard of it, and the person who wants
-- to use TrustIQ has to sell it to them first with nothing to show.
--
-- What this does NOT do, deliberately: make buyer_id or seller_id nullable.
-- Those columns are not null with foreign keys, and `transactions_creator_is_a
-- _party` depends on both. Every RLS policy, the identity gate, the actor
-- resolution in apply_transaction_event and the three copies of the state
-- machine all assume two real people. Relaxing that to carry a half-formed
-- contract would put a null through every one of them, and the tests that
-- would have to change are the tests that make the schema worth anything.
--
-- So the draft lives here instead, and a transaction is created at the moment
-- there are two people to hang it on. Nothing downstream of that moment
-- changes at all.
--
-- No email is sent. TrustIQ writing to a stranger is a different product with
-- different obligations, and the closed beta does not need it: the invitation
-- produces a code, and the person who wants the contract sends it themselves,
-- over whatever they already use. In this market that is WhatsApp, not email.
-- It also means this works today, rather than after an SMTP provider.
-- ---------------------------------------------------------------------------

create table app.contract_invitations (
  id            uuid primary key default gen_random_uuid(),

  -- Short enough to read down a phone, long enough not to be guessed. See
  -- app.new_invitation_code below for the alphabet and why it is that one.
  code          text not null unique
                  check (code ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}$'),

  inviter_id    uuid not null references public.profiles (id) on delete restrict,

  -- The address it is for. A code alone would be a bearer token: whoever it
  -- was forwarded to could take the other side of somebody else's contract.
  -- Claiming checks both.
  invited_email text not null check (position('@' in invited_email) > 1),

  -- Which side the person being invited is on, not which side the inviter is.
  -- Written from the invitee's point of view because that is who reads it.
  invitee_is    public.party_role not null,

  -- The draft. Same constraints as the columns these become, so an invitation
  -- cannot hold terms that a transaction would later refuse.
  description       text not null check (length(btrim(description)) between 1 and 500),
  terms             text not null check (length(btrim(terms)) between 1 and 10000),
  total_amount_fils public.fils not null check (total_amount_fils > 0),

  created_at    timestamptz not null default now(),

  -- An invitation that stays open forever is a contract offer that stays open
  -- forever. Thirty days, and the inviter can revoke sooner.
  expires_at    timestamptz not null default now() + interval '30 days',

  claimed_by     uuid references public.profiles (id) on delete restrict,
  claimed_at     timestamptz,
  transaction_id uuid references public.transactions (id) on delete restrict,
  revoked_at     timestamptz,

  -- Claimed means all three, or none of them.
  constraint invitations_claim_is_whole check (
    (claimed_by is null and claimed_at is null and transaction_id is null)
    or
    (claimed_by is not null and claimed_at is not null and transaction_id is not null)
  )
);

comment on table app.contract_invitations is
  'A contract draft addressed to an email that may not have an account yet. Becomes a transaction when somebody claims it. Service role and SECURITY DEFINER functions only: no client policy.';

create index invitations_email_idx on app.contract_invitations (lower(invited_email));
create index invitations_inviter_idx on app.contract_invitations (inviter_id, created_at desc);

-- ---------------------------------------------------------------------------
-- The code
--
-- Ambiguity is the enemy: this gets read aloud, retyped, and photographed.
-- No 0 or O, no 1 or I, and no vowels, which also keeps it from spelling
-- anything. 32 characters over 8 positions is about 40 bits, and a code is
-- useless without the address it was issued to, so guessing one buys nothing.
-- ---------------------------------------------------------------------------

create or replace function app.new_invitation_code()
returns text
language plpgsql
volatile
as $$
declare
  v_alphabet constant text := 'BCDFGHJKLMNPQRSTVWXYZ23456789';
  v_code text;
  v_try  integer := 0;
begin
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(
        v_alphabet,
        1 + floor(random() * length(v_alphabet))::integer,
        1
      );
      if i = 4 then v_code := v_code || '-'; end if;
    end loop;

    exit when not exists (
      select 1 from app.contract_invitations i where i.code = v_code
    );

    v_try := v_try + 1;
    if v_try > 20 then
      raise exception 'could not find an unused invitation code'
        using errcode = 'internal_error';
    end if;
  end loop;

  return v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- Creating one
-- ---------------------------------------------------------------------------

create or replace function public.invite_counterparty(
  p_email             text,
  p_invitee_is        public.party_role,
  p_description       text,
  p_terms             text,
  p_total_amount_fils bigint
)
returns app.contract_invitations
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me         uuid := auth.uid();
  v_email      text := lower(btrim(p_email));
  v_invitation app.contract_invitations;
begin
  if v_me is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  -- Inviting yourself is not a contract, and the transaction CHECK would
  -- refuse it later with a worse message.
  if exists (select 1 from public.profiles p where p.id = v_me and lower(p.email) = v_email) then
    raise exception 'a contract needs two different people'
      using errcode = 'check_violation';
  end if;

  -- If they already have an account there is nothing to invite them to. Say
  -- so rather than creating a code they will never need, because two ways to
  -- reach the same contract is two ways for it to go wrong.
  if exists (select 1 from public.profiles p where lower(p.email) = v_email) then
    raise exception 'that address already has a TrustIQ account, address the contract to them directly'
      using errcode = 'unique_violation';
  end if;

  insert into app.contract_invitations (
    code, inviter_id, invited_email, invitee_is,
    description, terms, total_amount_fils
  )
  values (
    app.new_invitation_code(), v_me, v_email, p_invitee_is,
    p_description, p_terms, p_total_amount_fils
  )
  returning * into v_invitation;

  return v_invitation;
end;
$$;

comment on function public.invite_counterparty is
  'Records a contract draft for an address with no account, and returns the code to share. No transaction exists until it is claimed.';

-- ---------------------------------------------------------------------------
-- Claiming one
--
-- The invitee runs this after signing up. It is the only moment a transaction
-- appears, and from then on the contract is an ordinary contract: the same
-- policies, the same state machine, the same identity gate.
-- ---------------------------------------------------------------------------

create or replace function public.claim_invitation(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_me         uuid := auth.uid();
  v_my_email   text;
  v_invitation app.contract_invitations;
  v_txn        uuid;
  v_buyer      uuid;
  v_seller     uuid;
begin
  if v_me is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  select lower(p.email) into v_my_email from public.profiles p where p.id = v_me;

  select * into v_invitation
  from app.contract_invitations i
  where i.code = upper(btrim(p_code))
  for update;

  -- One message for "no such code" and for "not addressed to you". The other
  -- way round, this function would tell anyone holding a wrong code whether
  -- it exists, which is a way to hunt for live invitations.
  if v_invitation.id is null or v_invitation.invited_email <> v_my_email then
    raise exception 'no invitation for you with that code'
      using errcode = 'no_data_found';
  end if;

  if v_invitation.revoked_at is not null then
    raise exception 'that invitation was withdrawn' using errcode = 'check_violation';
  end if;

  if v_invitation.claimed_at is not null then
    raise exception 'that invitation has already been used' using errcode = 'check_violation';
  end if;

  if v_invitation.expires_at <= now() then
    raise exception 'that invitation has expired' using errcode = 'check_violation';
  end if;

  if v_invitation.invitee_is = 'buyer' then
    v_buyer := v_me;
    v_seller := v_invitation.inviter_id;
  else
    v_buyer := v_invitation.inviter_id;
    v_seller := v_me;
  end if;

  insert into public.transactions (
    buyer_id, seller_id, description, terms, total_amount_fils, created_by
  )
  values (
    v_buyer, v_seller, v_invitation.description, v_invitation.terms,
    v_invitation.total_amount_fils, v_invitation.inviter_id
  )
  returning id into v_txn;

  -- Sent, not drafted. The inviter wrote the terms and shared the code; that
  -- was the sending. Leaving it in draft would leave it waiting on the person
  -- who already did their part.
  perform app.apply_transaction_event_as(
    v_txn,
    'submit',
    case when v_invitation.invitee_is = 'buyer' then 'seller' else 'buyer' end::public.actor_role
  );

  update app.contract_invitations
  set claimed_by = v_me, claimed_at = now(), transaction_id = v_txn
  where id = v_invitation.id;

  return v_txn;
end;
$$;

comment on function public.claim_invitation is
  'Turns an invitation into a real contract, once the person it was addressed to has an account. Checks the code and the address, because a code alone would be a bearer token.';

-- ---------------------------------------------------------------------------
-- Seeing and withdrawing
-- ---------------------------------------------------------------------------

create or replace function public.my_invitations()
returns table (
  id             uuid,
  code           text,
  invited_email  text,
  invitee_is     public.party_role,
  description    text,
  total_amount_fils bigint,
  created_at     timestamptz,
  expires_at     timestamptz,
  claimed_at     timestamptz,
  revoked_at     timestamptz,
  transaction_id uuid
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select i.id, i.code, i.invited_email, i.invitee_is, i.description,
         i.total_amount_fils, i.created_at, i.expires_at, i.claimed_at,
         i.revoked_at, i.transaction_id
  from app.contract_invitations i
  where i.inviter_id = auth.uid()
  order by i.created_at desc;
$$;

comment on function public.my_invitations is
  'What you have sent. Only ever your own: an invitation addressed to you is not visible until you claim it, because you reach it with the code, not by browsing.';

create or replace function public.revoke_invitation(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_rows integer;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  update app.contract_invitations
  set revoked_at = now()
  where id = p_id
    and inviter_id = auth.uid()
    and claimed_at is null
    and revoked_at is null;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    -- Already claimed is the case worth being clear about: the contract
    -- exists now and withdrawing the invitation would not undo it.
    raise exception 'nothing to withdraw: no such invitation of yours, or it was already used or withdrawn'
      using errcode = 'no_data_found';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- anon gets nothing, as with everything else in this schema. The table itself
-- has no client grant at all: it is reached only through these functions,
-- which is what keeps a signed-in person from reading the list of addresses
-- other people have invited.
-- ---------------------------------------------------------------------------

-- From PUBLIC as well as from anon, and the order matters less than the fact
-- that both are needed. Postgres grants EXECUTE on every new function to
-- PUBLIC on its own, and anon is a member of PUBLIC, so revoking from anon
-- alone leaves the grant standing through the group. The sweep test in
-- schema.test.sql caught exactly this on the first migration written after it
-- existed, which is the only reason it is right here.
revoke all on function public.invite_counterparty(text, public.party_role, text, text, bigint) from public, anon;
revoke all on function public.claim_invitation(text) from public, anon;
revoke all on function public.my_invitations() from public, anon;
revoke all on function public.revoke_invitation(uuid) from public, anon;
revoke all on function app.new_invitation_code() from public, anon, authenticated;

grant execute on function public.invite_counterparty(text, public.party_role, text, text, bigint) to authenticated;
grant execute on function public.claim_invitation(text) to authenticated;
grant execute on function public.my_invitations() to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;
