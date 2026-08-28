-- ---------------------------------------------------------------------------
-- 0019  Leaving
--
-- Eleven foreign keys hold a profile in place: contracts, evidence, disputes,
-- acceptances, invitations, identity checks. All of them RESTRICT, and that is
-- the product working rather than a mistake. A record one side can quietly
-- delete is worth nothing to the other, and somebody who was on the far end of
-- a contract does not lose their copy of it because their counterparty closed
-- an account.
--
-- Google Play requires a deletion path anyway, and it is right to. So the
-- answer is not "no" and it is not "yes, everything". It is:
--
--   Everything that identifies you goes. What the other party needs stays,
--   attached to a row that no longer names anybody.
--
-- Two paths, decided by the data rather than by policy:
--
--   Nothing points at the profile   the account is genuinely deleted, row and
--                                   all. Somebody who signed up and never did
--                                   anything is owed a real deletion.
--   Something points at it          the profile is emptied and kept as an
--                                   anonymous placeholder the contracts can
--                                   still hang from.
--
-- The tombstone address ends in .invalid, which RFC 2606 reserves and which
-- notifications_to_send already refuses to mail. An anonymised person stops
-- receiving anything without a suppression list existing anywhere.
-- ---------------------------------------------------------------------------

create table app.deletion_requests (
  id           bigint generated always as identity primary key,

  -- Not a foreign key. The whole point is that the row it refers to may be
  -- gone, and a constraint pointing at a deleted profile would either block
  -- the deletion or vanish with it, which defeats keeping a record at all.
  user_id      uuid not null,

  -- Kept so a person who asks later can be told what happened to their
  -- request. It is the one identifier that survives, and it survives here
  -- rather than on the profile.
  email        text not null,

  outcome      text not null check (outcome in ('deleted', 'anonymised')),

  -- Why the profile could not simply go, in plain words, so the answer to
  -- "what did you keep and why" does not have to be reconstructed.
  kept         text,

  requested_at timestamptz not null default now()
);

comment on table app.deletion_requests is
  'Append-only record of every account closure. Holds the address so a later question can be answered, and nothing else about the person.';

create trigger deletion_requests_immutable
  before update or delete on app.deletion_requests
  for each row execute function app.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Closing an account
--
-- Not callable by the person themselves. The edge function authenticates them
-- and then acts with the service role, because closing an account also means
-- neutralising the sign-in, which lives in auth and is reachable only from
-- there.
-- ---------------------------------------------------------------------------

create or replace function public.close_account(p_user_id uuid)
returns table (outcome text, kept text)
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_email  text;
  v_holds  text[] := '{}';
  v_kept   text;
  v_tomb   text;
begin
  perform app.assert_system_caller('closing an account');

  select p.email into v_email from public.profiles p where p.id = p_user_id;
  if v_email is null then
    raise exception 'no profile for %', p_user_id using errcode = 'no_data_found';
  end if;

  -- What is actually holding them, checked rather than assumed, so the answer
  -- given to the person is about their own account and not a generic list.
  if exists (select 1 from public.transactions t
             where p_user_id in (t.buyer_id, t.seller_id, t.created_by)) then
    v_holds := array_append(v_holds, 'contracts you were party to');
  end if;
  if exists (select 1 from public.evidence e where e.uploaded_by = p_user_id) then
    v_holds := array_append(v_holds, 'documents you filed as evidence');
  end if;
  if exists (select 1 from public.disputes d where d.opened_by = p_user_id)
     or exists (select 1 from public.dispute_acceptances a where a.user_id = p_user_id) then
    v_holds := array_append(v_holds, 'disputes you took part in');
  end if;
  if exists (select 1 from app.contract_invitations i
             where i.inviter_id = p_user_id or i.claimed_by = p_user_id) then
    v_holds := array_append(v_holds, 'invitations you sent');
  end if;
  if exists (select 1 from app.identity_checks c where c.user_id = p_user_id) then
    v_holds := array_append(v_holds, 'the record that your identity was checked');
  end if;
  if exists (select 1 from app.reviewers r where r.user_id = p_user_id) then
    v_holds := array_append(v_holds, 'your place on the reviewer list');
  end if;

  if array_length(v_holds, 1) is null then
    -- Nothing points at them. Somebody who signed up and did nothing is owed
    -- a real deletion, not a tombstone.
    delete from public.profiles where id = p_user_id;
    insert into app.deletion_requests (user_id, email, outcome, kept)
    values (p_user_id, v_email, 'deleted', null);
    return query select 'deleted'::text, null::text;
    return;
  end if;

  v_kept := array_to_string(v_holds, ', ');

  -- .invalid is reserved by RFC 2606 and can never be delivered to, and
  -- notifications_to_send already refuses to mail a reserved domain. The
  -- tombstone therefore stops the post without a suppression list.
  v_tomb := 'closed-' || replace(p_user_id::text, '-', '') || '@deleted.invalid';

  update public.profiles
  set full_name            = 'Closed account',
      email                = v_tomb,
      phone                = null,
      preferred_locale     = null,
      -- The verification went with the person. Leaving it standing would mean
      -- a row nobody can vouch for still claiming somebody was checked.
      identity_verified_at = null,
      identity_provider    = null
  where id = p_user_id;

  insert into app.deletion_requests (user_id, email, outcome, kept)
  values (p_user_id, v_email, 'anonymised', v_kept);

  return query select 'anonymised'::text, v_kept;
end;
$$;

comment on function public.close_account is
  'Deletes a profile nothing points at, and empties one that something does. Never removes a contract: the other party keeps their copy either way.';

revoke all on function public.close_account(uuid) from public, anon, authenticated;
grant execute on function public.close_account(uuid) to service_role;
