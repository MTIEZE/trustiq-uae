-- ---------------------------------------------------------------------------
-- Schema test suite.
--
-- Plain SQL assertions, no pgTAP dependency. Every check raises on failure, so
-- the script exits non-zero and CI goes red. Run with scripts/db-test.sh.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on
\timing off

create or replace function pg_temp.check(p_condition boolean, p_label text)
returns void
language plpgsql
as $$
begin
  if p_condition is not true then
    raise exception 'FAIL: %', p_label;
  end if;
  raise notice '  ok  %', p_label;
end;
$$;

create or replace function pg_temp.expect_error(p_sql text, p_label text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice '  ok  % (refused: %)', p_label, replace(sqlerrm, e'\n', ' ');
    return;
  end;
  raise exception 'FAIL: % (statement was allowed but should have been refused)', p_label;
end;
$$;

-- Deferred constraint triggers only fire at COMMIT, and psql cannot catch a
-- failing commit inside this harness. Forcing them immediate inside a
-- subtransaction exercises the real trigger at a point where we can observe it.
create or replace function pg_temp.expect_deferred_error(p_sql text, p_label text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
    set constraints all immediate;
    raise exception using errcode = 'TRIQ1', message = 'constraint did not fire';
  exception
    when sqlstate 'TRIQ1' then
      raise exception 'FAIL: % (the deferred constraint did not fire)', p_label;
    when others then
      raise notice '  ok  % (refused: %)', p_label, replace(sqlerrm, e'\n', ' ');
  end;
end;
$$;

\echo ''
\echo '== Structural =='

-- Every table in public must have RLS on. A new table without it is a data leak.
do $$
declare
  v_missing text;
begin
  select string_agg(c.relname, ', ')
  into v_missing
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity;

  perform pg_temp.check(v_missing is null,
    'every public table has row level security enabled' ||
    coalesce(' (missing: ' || v_missing || ')', ''));
end
$$;

-- Nothing in `app` may be readable by client roles.
do $$
declare
  v_leaks text;
begin
  select string_agg(distinct c.relname, ', ')
  into v_leaks
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'app'
    and c.relkind = 'r'
    and (
      has_table_privilege('anon', c.oid, 'SELECT')
      or has_table_privilege('authenticated', c.oid, 'SELECT')
    );

  perform pg_temp.check(v_leaks is null,
    'internal app tables are not readable by client roles' ||
    coalesce(' (leaking: ' || v_leaks || ')', ''));
end
$$;

-- Money must never be stored as a floating point type.
do $$
declare
  v_bad text;
begin
  select string_agg(c.relname || '.' || a.attname, ', ')
  into v_bad
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_type t on t.oid = a.atttypid
  where n.nspname = 'public'
    and c.relkind = 'r'
    and a.attnum > 0
    and not a.attisdropped
    and a.attname like '%_fils'
    and t.typname not in ('int8', 'fils');

  perform pg_temp.check(v_bad is null,
    'every *_fils column is an integer type' || coalesce(' (bad: ' || v_bad || ')', ''));
end
$$;

\echo ''
\echo '== Money domain =='

select pg_temp.expect_error(
  $q$ select 9223372036855::public.fils $q$,
  'fils domain rejects an amount above the supported ceiling');

select pg_temp.expect_error(
  $q$ select (-9223372036855)::public.fils $q$,
  'fils domain rejects an amount below the supported floor');

select pg_temp.check((50000::public.fils) = 50000, 'fils domain accepts 500.00 AED as 50000 fils');

\echo ''
\echo '== Fixtures =='

-- Two verified parties and one unverified third party.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'ahmed@startup.ae'),
  ('22222222-2222-2222-2222-222222222222', 'sara@design.ae'),
  ('33333333-3333-3333-3333-333333333333', 'nosy@example.ae');

insert into public.profiles (id, full_name, email, identity_verified_at, identity_provider) values
  ('11111111-1111-1111-1111-111111111111', 'Ahmed Al-Rashid',   'ahmed@startup.ae', now(), 'uae_pass'),
  ('22222222-2222-2222-2222-222222222222', 'Sara Design Studio','sara@design.ae',   now(), 'uae_pass'),
  ('33333333-3333-3333-3333-333333333333', 'Unrelated Person',  'nosy@example.ae',  null,  null);

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'Logo design for a startup',
   'Deliver 3 logo concepts within 7 days. Two rounds of revision. SVG + PNG.',
   50000,
   '11111111-1111-1111-1111-111111111111');

select pg_temp.check(
  (select state from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'draft',
  'a new contract starts as draft');

\echo ''
\echo '== State machine =='

-- Direct state writes are refused, even as superuser.
select pg_temp.expect_error(
  $q$ update public.transactions set state = 'completed'
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $q$,
  'a direct UPDATE of transactions.state is blocked by the guard');

-- Walk the happy path as the real parties.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'submit');

select pg_temp.check(
  (select state from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'pending_acceptance',
  'buyer submits the draft, contract becomes pending_acceptance');

-- The buyer cannot declare delivery: that is the seller's move, and not from
-- this state either.
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'mark_delivered') $q$,
  'an event that is not legal from the current state is refused');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'accept');

select pg_temp.check(
  (select state from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'active',
  'seller accepts, contract becomes active');

-- Actor authorization: only the seller may mark delivery.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'mark_delivered') $q$,
  'the buyer may not mark delivery on the seller''s behalf');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'mark_delivered');

-- And only the buyer may confirm it.
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'confirm_delivery') $q$,
  'the seller may not confirm their own delivery');

-- A stranger cannot touch the contract at all.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'confirm_delivery') $q$,
  'a non-party cannot fire any event');

\echo ''
\echo '== Row level security =='

select pg_temp.check(
  (select count(*) from public.transactions) = 0,
  'a non-party sees no rows in transactions');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.check(
  (select count(*) from public.transactions) = 1,
  'the buyer sees their own contract');

select pg_temp.check(
  (select count(*) from public.profiles) = 2,
  'the buyer sees their own profile and the counterparty, but not a stranger');

-- Self-verification must be impossible. The WITH CHECK re-reads the stored row,
-- so raising your own identity_verified_at fails the policy.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ update public.profiles set identity_verified_at = now() where id = auth.uid() $q$,
  'a user cannot mark their own identity as verified');

-- Editing your own contact details still works.
update public.profiles set full_name = 'Renamed Person' where id = auth.uid();
select pg_temp.check(
  (select full_name from public.profiles where id = auth.uid()) = 'Renamed Person',
  'a user can still edit their own contact details');

-- RLS filters rather than errors: an update aimed at someone else's row simply
-- matches nothing. Verified from outside the policy.
update public.profiles set full_name = 'Hijacked'
where id = '11111111-1111-1111-1111-111111111111';

reset role;
select pg_temp.check(
  (select full_name from public.profiles where id = '11111111-1111-1111-1111-111111111111')
    = 'Ahmed Al-Rashid',
  'an update aimed at another user''s profile changes nothing');

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

\echo ''
\echo '== Evidence =='

reset role;

insert into public.evidence
  (id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256)
values
  ('ee000000-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'evidence/aaaa/contract.pdf', 'contract.pdf', 'application/pdf', 12345,
   repeat('a', 64)),
  ('ee000000-0000-0000-0000-000000000002',
   'aaaaaaaa-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'seller',
   'evidence/aaaa/delivery.zip', 'delivery.zip', 'application/zip', 98765,
   repeat('b', 64));

select pg_temp.expect_error(
  $q$ update public.evidence set filename = 'tampered.pdf'
      where id = 'ee000000-0000-0000-0000-000000000001' $q$,
  'evidence rows cannot be updated, even by a superuser');

select pg_temp.expect_error(
  $q$ delete from public.evidence where id = 'ee000000-0000-0000-0000-000000000001' $q$,
  'evidence rows cannot be deleted');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256)
      values ('aaaaaaaa-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'seller',
              'evidence/aaaa/x.pdf', 'x.pdf', 'application/pdf', 10, repeat('c', 64)) $q$,
  'the declared uploader role must match the actual side of the contract');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256)
      values ('aaaaaaaa-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaaa/dup.pdf', 'dup.pdf', 'application/pdf', 10, repeat('a', 64)) $q$,
  'the same file digest cannot be filed twice on one contract');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256)
      values ('aaaaaaaa-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaaa/bad.pdf', 'bad.pdf', 'application/pdf', 10, 'NOTAHASH') $q$,
  'a malformed SHA-256 is rejected');

\echo ''
\echo '== Evidence is server-written only (the SHA-256 hole) =='

-- A party can read the evidence on their own contract...
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select pg_temp.check(
  (select count(*) from public.evidence) = 2,
  'a party can read the evidence on their own contract');

-- ...but cannot write a row, which is what would let them choose the digest.
-- RLS filters SELECT silently; on INSERT with no policy it raises.
select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256)
      values ('aaaaaaaa-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaaa/forged.pdf', 'forged.pdf', 'application/pdf', 10,
              repeat('d', 64)) $q$,
  'a party cannot insert an evidence row, so cannot choose its own digest');

reset role;

select pg_temp.check(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'evidence' and cmd = 'INSERT') = 0,
  'no INSERT policy exists on evidence for any client role');

select pg_temp.check(
  (select public from storage.buckets where id = 'evidence') = false,
  'the evidence bucket is private');

select pg_temp.check(
  (select count(*) from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd <> 'SELECT') = 0,
  'clients cannot write to storage, so a stored object cannot be swapped after hashing');

\echo ''
\echo '== Disputes and proposals =='

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'open_dispute');
select set_config('request.jwt.claim.sub', '', false);

insert into public.disputes
  (id, transaction_id, opened_by, opened_by_role, buyer_claim, seller_claim, disputed_amount_fils)
values
  ('dd000000-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'The delivered work does not match the brief.',
   'I delivered exactly what was specified.',
   50000);

-- Only one live dispute per contract.
select pg_temp.expect_error(
  $q$ insert into public.disputes
        (transaction_id, opened_by, opened_by_role, disputed_amount_fils)
      values ('aaaaaaaa-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'buyer', 50000) $q$,
  'a contract cannot have two open disputes at once');

-- The allocation invariant: one fil short must not be storable.
select pg_temp.expect_error(
  $q$ insert into public.resolution_proposals
        (dispute_id, source, decision, summary, disputed_amount_fils,
         seller_amount_fils, buyer_amount_fils, confidence, model_id)
      values ('dd000000-0000-0000-0000-000000000001', 'ai', 'split', 'Ambiguous case.',
              50000, 30000, 19999, 0.62, 'claude-sonnet-5') $q$,
  'an allocation that is one fil short is refused');

select pg_temp.expect_error(
  $q$ insert into public.resolution_proposals
        (dispute_id, source, decision, summary, disputed_amount_fils,
         seller_amount_fils, buyer_amount_fils, confidence, model_id)
      values ('dd000000-0000-0000-0000-000000000001', 'ai', 'refund_to_buyer', 'Contradictory.',
              50000, 30000, 20000, 0.62, 'claude-sonnet-5') $q$,
  'a decision that contradicts its own allocation is refused');

select pg_temp.expect_error(
  $q$ insert into public.resolution_proposals
        (dispute_id, source, decision, summary, disputed_amount_fils,
         seller_amount_fils, buyer_amount_fils, confidence, model_id)
      values ('dd000000-0000-0000-0000-000000000001', 'ai', 'split', 'Wrong total.',
              49000, 29000, 20000, 0.62, 'claude-sonnet-5') $q$,
  'a proposal for a different amount than the dispute is refused');

select pg_temp.expect_error(
  $q$ insert into public.resolution_proposals
        (dispute_id, source, decision, summary, disputed_amount_fils,
         seller_amount_fils, buyer_amount_fils)
      values ('dd000000-0000-0000-0000-000000000001', 'ai', 'split', 'Unattributed AI output.',
              50000, 30000, 20000) $q$,
  'an AI proposal without a model id and confidence is refused');

-- The valid one.
insert into public.resolution_proposals
  (id, dispute_id, source, decision, summary, disputed_amount_fils,
   seller_amount_fils, buyer_amount_fils, confidence, model_id)
values
  ('99000000-0000-0000-0000-000000000001',
   'dd000000-0000-0000-0000-000000000001', 'ai', 'split',
   'Delivery was on time but quality could not be verified from the evidence.',
   50000, 30000, 20000, 0.62, 'claude-sonnet-5');

select pg_temp.check(true, 'a balanced, attributed proposal is accepted');

-- Grounding: a finding with no citation must not survive commit.
select pg_temp.expect_deferred_error(
  $q$ insert into public.resolution_findings (id, proposal_id, position, statement)
      values ('ff000000-0000-0000-0000-000000000001',
              '99000000-0000-0000-0000-000000000001', 0, 'The work was clearly substandard.') $q$,
  'a finding citing no evidence is refused');

-- A properly grounded finding commits.
begin;
  insert into public.resolution_findings (id, proposal_id, position, statement)
  values ('ff000000-0000-0000-0000-000000000002',
          '99000000-0000-0000-0000-000000000001', 0, 'A signed contract exists.');
  insert into public.resolution_finding_evidence (finding_id, evidence_id)
  values ('ff000000-0000-0000-0000-000000000002', 'ee000000-0000-0000-0000-000000000001');
commit;
select pg_temp.check(true, 'a grounded finding commits');

-- A citation to evidence nobody submitted cannot be stored, even from a finding
-- that does exist. This is the model hallucinating a document, made unstorable.
select pg_temp.expect_error(
  $q$ insert into public.resolution_finding_evidence (finding_id, evidence_id)
      values ('ff000000-0000-0000-0000-000000000002',
              'ee000000-0000-0000-0000-0000000000ff') $q$,
  'a citation to non-existent evidence is refused by the evidence foreign key');

-- Evidence cannot be deleted out from under a resolution that cites it. The
-- append-only trigger stops this first; the join's ON DELETE RESTRICT is the
-- second line of defence if that trigger is ever removed.
select pg_temp.expect_error(
  $q$ delete from public.evidence where id = 'ee000000-0000-0000-0000-000000000001' $q$,
  'evidence cited by a resolution cannot be removed');

\echo ''
\echo '== Acceptance requires both parties =='

-- Move the dispute to proposal_issued. With no JWT claim set, the caller is
-- resolved as `system`, which is what the server-side pipeline is.
select set_config('request.jwt.claim.sub', '', false);
select public.apply_dispute_event('dd000000-0000-0000-0000-000000000001', 'submit_for_ai');
select public.apply_dispute_event('dd000000-0000-0000-0000-000000000001', 'issue_proposal');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000001') = 'proposal_issued',
  'the pipeline moves the dispute to proposal_issued');

-- One party accepting is not enough.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.accept_resolution_proposal('99000000-0000-0000-0000-000000000001');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000001') = 'proposal_issued',
  'one acceptance does not close the dispute');

-- Replaying the same acceptance changes nothing.
select public.accept_resolution_proposal('99000000-0000-0000-0000-000000000001');
select public.accept_resolution_proposal('99000000-0000-0000-0000-000000000001');

select pg_temp.check(
  (select count(*) from public.dispute_acceptances
   where proposal_id = '99000000-0000-0000-0000-000000000001') = 1,
  'a replayed acceptance is idempotent, not a second vote');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000001') = 'proposal_issued',
  'replaying one party''s acceptance still does not close the dispute');

-- The second party closes it, and the contract resolves with it.
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.accept_resolution_proposal('99000000-0000-0000-0000-000000000001');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000001') = 'accepted',
  'both acceptances close the dispute');

select pg_temp.check(
  (select state from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'resolved',
  'closing the dispute resolves the parent contract');

\echo ''
\echo '== Audit trail =='

select pg_temp.check(
  (select count(*) from public.transaction_events
   where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 5,
  'every contract state change was logged');

select pg_temp.check(
  (select to_state from public.transaction_events
   where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001'
   order by occurred_at desc, id desc limit 1) = 'resolved',
  'the final logged state matches the contract');

select pg_temp.check(
  (select actor from public.transaction_events
   where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and event = 'resolve_dispute') = 'system',
  'the resolution was recorded as a system action, not a party action');

select pg_temp.expect_error(
  $q$ delete from public.transaction_events
      where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001' $q$,
  'the audit log cannot be deleted');

select pg_temp.expect_error(
  $q$ update public.transaction_events set actor = 'buyer'
      where event = 'resolve_dispute' $q$,
  'the audit log cannot be rewritten');

\echo ''
\echo '== Terminal states =='

select pg_temp.expect_error(
  $q$ select public.apply_dispute_event('dd000000-0000-0000-0000-000000000001', 'reject_proposal') $q$,
  'a closed dispute accepts no further events');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000001', 'open_dispute') $q$,
  'a resolved contract accepts no further events');

reset role;

\echo ''
\echo '== Identity gate =='

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333333',
   'Contract with an unverified counterparty',
   'Terms.', 10000,
   '11111111-1111-1111-1111-111111111111');

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000002', 'submit');

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000002', 'accept') $q$,
  'a contract cannot become active while a party is unverified');

reset role;

\echo ''
\echo '== Milestones =='

select pg_temp.expect_deferred_error(
  $q$ insert into public.milestones (transaction_id, position, title, amount_fils)
      values ('aaaaaaaa-0000-0000-0000-000000000002', 0, 'Too much', 20000) $q$,
  'milestones cannot promise more than the contract is worth');

-- Milestones that fit are accepted.
insert into public.milestones (transaction_id, position, title, amount_fils) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 0, 'First half',  5000),
  ('aaaaaaaa-0000-0000-0000-000000000002', 1, 'Second half', 5000);

select pg_temp.check(
  (select sum(amount_fils) from public.milestones
   where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000002') = 10000,
  'milestones that sum to the contract total are accepted');


\echo ''
\echo '== A bad id is reported as a bad id =='

-- Both functions refuse an unknown id, and both say why it was refused rather
-- than blaming the caller's permissions for the caller's typo.
select pg_temp.expect_error(
  $q$ select public.apply_transaction_event('aaaaaaaa-dead-dead-dead-aaaaaaaaaaaa', 'submit') $q$,
  'an unknown transaction id is reported as not found');

select pg_temp.expect_error(
  $q$ select public.apply_dispute_event('dddddddd-dead-dead-dead-dddddddddddd', 'submit_for_ai') $q$,
  'an unknown dispute id is reported as not found');

do $$
declare
  v_message text;
begin
  begin
    perform public.apply_dispute_event('dddddddd-dead-dead-dead-dddddddddddd', 'submit_for_ai');
  exception when others then
    v_message := sqlerrm;
  end;
  perform pg_temp.check(
    v_message like '%not found%',
    'the message says "not found" rather than blaming the caller (' || coalesce(v_message, 'no error') || ')');
end
$$;

\echo ''
\echo '== issue_ai_proposal writes a whole proposal or none of it =='

-- A third contract, walked to `disputed`, so the proposal path can be tested
-- without disturbing the acceptance fixtures above.
insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'Landing page copy',
   'Deliver 800 words of landing page copy within 5 days.',
   50000,
   '11111111-1111-1111-1111-111111111111');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000003', 'submit');
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000003', 'accept');
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000003', 'mark_delivered');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000003', 'open_dispute');
select set_config('request.jwt.claim.sub', '', false);

insert into public.evidence
  (id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename, content_type, byte_size, sha256)
values
  ('ee000000-0000-0000-0000-000000000003',
   'aaaaaaaa-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'evidence/aaa3/brief.txt', 'brief.txt', 'text/plain', 400, repeat('3', 64)),
  ('ee000000-0000-0000-0000-000000000004',
   'aaaaaaaa-0000-0000-0000-000000000003',
   '22222222-2222-2222-2222-222222222222', 'seller',
   'evidence/aaa3/draft.txt', 'draft.txt', 'text/plain', 900, repeat('4', 64));

insert into public.disputes
  (id, transaction_id, opened_by, opened_by_role, buyer_claim, seller_claim, disputed_amount_fils)
values
  ('dd000000-0000-0000-0000-000000000002',
   'aaaaaaaa-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'The copy came in at 300 words, not 800.',
   'The brief changed halfway through.',
   50000);

select public.apply_dispute_event('dd000000-0000-0000-0000-000000000002', 'submit_for_ai');

-- A party must not be able to author the proposal that decides their own case.
-- Two independent barriers, tested separately because either one alone would
-- be enough to hide a hole in the other.
select pg_temp.check(
  not has_function_privilege('authenticated',
    'public.issue_ai_proposal(uuid, public.resolution_decision, text, bigint, bigint, bigint, numeric, text, timestamptz, jsonb)',
    'EXECUTE'),
  'authenticated holds no EXECUTE grant on issue_ai_proposal');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.expect_error(
  $q$ select public.issue_ai_proposal(
        'dd000000-0000-0000-0000-000000000002', 'split', 'Written by a party.',
        50000, 30000, 20000, 0.9, 'claude-opus-5', now(),
        '[{"statement":"Mine.","evidenceIds":["ee000000-0000-0000-0000-000000000003"]}]'::jsonb) $q$,
  'issue_ai_proposal refuses a caller holding a user session');
select set_config('request.jwt.claim.sub', '', false);

-- An unknown dispute is reported as unknown, not as a permissions problem.
select pg_temp.expect_error(
  $q$ select public.issue_ai_proposal(
        'dddddddd-dead-dead-dead-dddddddddddd', 'split', 'Nowhere to put this.',
        50000, 30000, 20000, 0.9, 'claude-opus-5', now(),
        '[{"statement":"x","evidenceIds":["ee000000-0000-0000-0000-000000000003"]}]'::jsonb) $q$,
  'issue_ai_proposal refuses an unknown dispute id');

-- A proposal with no findings at all is not a proposal.
select pg_temp.expect_error(
  $q$ select public.issue_ai_proposal(
        'dd000000-0000-0000-0000-000000000002', 'split', 'No basis given.',
        50000, 30000, 20000, 0.9, 'claude-opus-5', now(), '[]'::jsonb) $q$,
  'issue_ai_proposal refuses a proposal carrying no findings');

-- The hallucinated citation, arriving through the function rather than as a
-- bare insert. The foreign key fires inside the call and takes the proposal
-- row with it.
select pg_temp.expect_error(
  $q$ select public.issue_ai_proposal(
        'dd000000-0000-0000-0000-000000000002', 'split', 'Cites a document nobody filed.',
        50000, 30000, 20000, 0.9, 'claude-opus-5', now(),
        '[{"statement":"There was a signed addendum.",
           "evidenceIds":["ee000000-0000-0000-0000-0000000000fe"]}]'::jsonb) $q$,
  'issue_ai_proposal refuses a finding citing evidence nobody submitted');

select pg_temp.check(
  (select count(*) from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000002') = 0,
  'the refused call left no proposal row behind');

-- An uncited statement. The grounding trigger is deferred, so it only fires
-- when constraints are forced immediate; the whole call unwinds when it does.
select pg_temp.expect_deferred_error(
  $q$ select public.issue_ai_proposal(
        'dd000000-0000-0000-0000-000000000002', 'split', 'One statement floats free.',
        50000, 30000, 20000, 0.9, 'claude-opus-5', now(),
        '[{"statement":"The brief asked for 800 words.",
           "evidenceIds":["ee000000-0000-0000-0000-000000000003"]},
          {"statement":"The seller was obviously careless.",
           "evidenceIds":[]}]'::jsonb) $q$,
  'issue_ai_proposal refuses a proposal containing an ungrounded finding');

select pg_temp.check(
  (select count(*) from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000002') = 0,
  'the ungrounded proposal left nothing behind either');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000002') = 'ai_review',
  'a refused proposal leaves the dispute where it was');

-- The whole thing, the way the pipeline calls it. This is the case that used to
-- fail: findings inserted before their citations, in one transaction.
do $$
declare
  v_id uuid;
begin
  v_id := public.issue_ai_proposal(
    'dd000000-0000-0000-0000-000000000002', 'split',
    'The copy fell short of the agreed length, but a usable draft was delivered.',
    50000, 30000, 20000, 0.78, 'claude-opus-5', now(),
    '[{"statement":"The brief specified 800 words.",
       "evidenceIds":["ee000000-0000-0000-0000-000000000003"]},
      {"statement":"The delivered draft was shorter than agreed.",
       "evidenceIds":["ee000000-0000-0000-0000-000000000003",
                      "ee000000-0000-0000-0000-000000000004"]}]'::jsonb);

  -- Force the deferred grounding check here rather than at the end of the
  -- suite, so this assertion is what proves it passed.
  set constraints all immediate;

  perform pg_temp.check(v_id is not null, 'issue_ai_proposal returns the new proposal id');
end
$$;

select pg_temp.check(
  (select count(*) from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000002') = 1,
  'the proposal was stored');

select pg_temp.check(
  (select count(*) from public.resolution_findings f
   join public.resolution_proposals p on p.id = f.proposal_id
   where p.dispute_id = 'dd000000-0000-0000-0000-000000000002') = 2,
  'both findings were stored in the same call');

select pg_temp.check(
  (select count(*) from public.resolution_finding_evidence fe
   join public.resolution_findings f on f.id = fe.finding_id
   join public.resolution_proposals p on p.id = f.proposal_id
   where p.dispute_id = 'dd000000-0000-0000-0000-000000000002') = 3,
  'all three citations were stored in the same call');

select pg_temp.check(
  (select array_agg(f.position order by f.position)
   from public.resolution_findings f
   join public.resolution_proposals p on p.id = f.proposal_id
   where p.dispute_id = 'dd000000-0000-0000-0000-000000000002') = array[0, 1],
  'findings keep the order the pipeline sent them in');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000002') = 'proposal_issued',
  'the same call publishes the proposal to the parties');

select pg_temp.check(
  (select actor from public.dispute_events
   where dispute_id = 'dd000000-0000-0000-0000-000000000002'
   order by occurred_at desc, id desc limit 1) = 'system',
  'the publish is recorded as a system action, not a party''s');

\echo ''
\echo '== Extracted text says which kind of nothing it is =='

-- Rows filed before 0010 keep a status that is not a judgement about the file.
select pg_temp.check(
  (select extraction_status from public.evidence
   where id = 'ee000000-0000-0000-0000-000000000001') = 'not_attempted',
  'a row inserted without a status defaults to not_attempted, not to unsupported');

select pg_temp.check(
  (select extracted_text from public.evidence
   where id = 'ee000000-0000-0000-0000-000000000001') is null,
  'a not_attempted row carries no text');

-- The pair the server actually writes.
insert into public.evidence
  (id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
   content_type, byte_size, sha256, extracted_text, extraction_status)
values
  ('ee000000-0000-0000-0000-000000000010',
   'aaaaaaaa-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'evidence/aaa3/notes.txt', 'notes.txt', 'text/plain', 64, repeat('e', 64),
   'The brief asked for 800 words of landing page copy.', 'extracted');

select pg_temp.check(true, 'a row with text and status extracted is accepted');

insert into public.evidence
  (id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
   content_type, byte_size, sha256, extraction_status)
values
  ('ee000000-0000-0000-0000-000000000011',
   'aaaaaaaa-0000-0000-0000-000000000003',
   '22222222-2222-2222-2222-222222222222', 'seller',
   'evidence/aaa3/shot.png', 'shot.png', 'image/png', 8000, repeat('f', 64),
   'unsupported');

select pg_temp.check(true, 'a row with no text and status unsupported is accepted');

-- Status and text must agree. Either half alone is a row that lies about
-- itself: a proposal could be built from a document the model never saw, or a
-- reader could skip text that is really there.
select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256, extraction_status)
      values ('aaaaaaaa-0000-0000-0000-000000000003',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaa3/a.txt', 'a.txt', 'text/plain', 10, repeat('1', 64),
              'extracted') $q$,
  'status extracted with no text is refused');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256, extracted_text, extraction_status)
      values ('aaaaaaaa-0000-0000-0000-000000000003',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaa3/b.txt', 'b.txt', 'text/plain', 10, repeat('2', 64),
              'text nobody will read', 'failed') $q$,
  'status failed carrying text is refused');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256, extracted_text, extraction_status)
      values ('aaaaaaaa-0000-0000-0000-000000000003',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaa3/c.txt', 'c.txt', 'text/plain', 10, repeat('3', 64),
              '   ', 'extracted') $q$,
  'status extracted with nothing but whitespace is refused');

select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256, extraction_status)
      values ('aaaaaaaa-0000-0000-0000-000000000003',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaa3/d.txt', 'd.txt', 'text/plain', 10, repeat('4', 64),
              'partially_read') $q$,
  'a status the code never produces is refused');

-- The ceiling exists so one document cannot swallow the prompt.
select pg_temp.expect_error(
  $q$ insert into public.evidence
        (transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
         content_type, byte_size, sha256, extracted_text, extraction_status)
      values ('aaaaaaaa-0000-0000-0000-000000000003',
              '11111111-1111-1111-1111-111111111111', 'buyer',
              'evidence/aaa3/e.txt', 'e.txt', 'text/plain', 10, repeat('5', 64),
              repeat('x', 20001), 'truncated') $q$,
  'extracted text above the ceiling is refused');

-- Append-only covers the new columns too: the text is part of the record, not
-- a cache that can be refreshed later.
select pg_temp.expect_error(
  $q$ update public.evidence
      set extracted_text = 'something else'
      where id = 'ee000000-0000-0000-0000-000000000010' $q$,
  'extracted text cannot be rewritten after the fact');

\echo ''
\echo '== You can see who is on the other side, and nobody else =='

set role authenticated;

-- 1111 is party to contracts with both 2222 and 3333, so all three are
-- visible. The fixtures decide that, not this assertion.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select pg_temp.check(
  (select count(*) from public.visible_profiles) = 3,
  'a party sees themselves and everyone they share a contract with (saw ' ||
  (select string_agg(coalesce(full_name, id::text), ', ' order by id) from public.visible_profiles) || ')');

select pg_temp.check(
  (select full_name from public.visible_profiles
   where id = '22222222-2222-2222-2222-222222222222') = 'Sara Design Studio',
  'the counterparty is named, so a contract screen can render both sides');

select pg_temp.check(
  (select identity_verified_at is not null from public.visible_profiles
   where id = '22222222-2222-2222-2222-222222222222'),
  'a verified counterparty reads as verified, so the identity gate can be explained');

select pg_temp.check(
  (select identity_verified_at is null from public.visible_profiles
   where id = '33333333-3333-3333-3333-333333333333'),
  'an unverified counterparty reads as unverified, which is what blocks the gate');

-- The isolation test, from the side that can actually show it. 3333 is party
-- to one contract, with 1111, and has never met 2222.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);

select pg_temp.check(
  (select count(*) from public.visible_profiles) = 2,
  'someone on one contract sees only themselves and that counterparty (saw ' ||
  (select string_agg(coalesce(full_name, id::text), ', ' order by id) from public.visible_profiles) || ')');

select pg_temp.check(
  not exists (select 1 from public.visible_profiles
              where id = '22222222-2222-2222-2222-222222222222'),
  'a stranger you share no contract with stays invisible');

-- The view withholds columns the table has. This is the only place in the
-- schema where that is possible, so it is worth asserting rather than assuming.
select pg_temp.check(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'visible_profiles'
      and column_name in ('email', 'phone', 'identity_provider')
  ),
  'the view exposes no contact details, only name and verification');

reset role;

\echo ''
\echo '== Addressing a contract to someone =='

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select pg_temp.check(
  public.find_counterparty('sara@design.ae') = '22222222-2222-2222-2222-222222222222',
  'an email resolves to the person who holds it');

select pg_temp.check(
  public.find_counterparty('  SARA@Design.AE  ') = '22222222-2222-2222-2222-222222222222',
  'the lookup ignores case and surrounding space, because people type addresses');

select pg_temp.check(
  public.find_counterparty('nobody@nowhere.ae') is null,
  'an address nobody holds returns null rather than raising');

select pg_temp.expect_error(
  $q$ select public.find_counterparty('ahmed@startup.ae') $q$,
  'addressing a contract to yourself is refused');

reset role;

-- Signed out, the lookup is not an open directory.
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.expect_error(
  $q$ select public.find_counterparty('sara@design.ae') $q$,
  'the lookup refuses a caller with no session');

select pg_temp.check(
  not has_function_privilege('anon', 'public.find_counterparty(text)', 'EXECUTE'),
  'anon holds no grant on the lookup');

-- anon does hold SELECT on this view: Supabase grants it on every table and
-- view in `public`, and taking it away would be fighting the platform for no
-- gain. What protects the view is its own WHERE clause, which resolves to
-- auth.uid(). Asserting the grant was absent tested a thing that is not true
-- of the deployed project. Asserting the rows are empty tests the thing that
-- actually stands between an anonymous caller and every name in the database.
set role anon;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select count(*) from public.visible_profiles) = 0,
  'the profile view yields nothing to a caller with no session');

reset role;

\echo ''
\echo '== The human a refused proposal goes to =='

-- A fourth contract, walked to a dispute the model gave up on.
insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', 'review@trustiq.ae'),
  ('55555555-5555-5555-5555-555555555555', 'review2@trustiq.ae');

insert into public.profiles (id, full_name, email) values
  ('44444444-4444-4444-4444-444444444444', 'Reviewer One', 'review@trustiq.ae'),
  ('55555555-5555-5555-5555-555555555555', 'Reviewer Two', 'review2@trustiq.ae');

insert into app.reviewers (user_id) values
  ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555');

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'Product photography',
   'Forty retouched product photographs within ten days.',
   80000,
   '11111111-1111-1111-1111-111111111111');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000004', 'submit');
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000004', 'accept');
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000004', 'mark_delivered');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000004', 'open_dispute');
select set_config('request.jwt.claim.sub', '', false);

insert into public.evidence
  (id, transaction_id, uploaded_by, uploaded_by_role, storage_path, filename,
   content_type, byte_size, sha256, extracted_text, extraction_status)
values
  ('ee000000-0000-0000-0000-000000000020',
   'aaaaaaaa-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'evidence/aaa4/brief.txt', 'brief.txt', 'text/plain', 90, repeat('7', 64),
   'Forty photographs, ten days, retouched.', 'extracted');

insert into public.disputes
  (id, transaction_id, opened_by, opened_by_role, buyer_claim, seller_claim, disputed_amount_fils)
values
  ('dd000000-0000-0000-0000-000000000003',
   'aaaaaaaa-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111', 'buyer',
   'Twenty two photographs arrived, not forty.',
   'The shoot was cut short when the client cancelled the second day.',
   80000);

-- The model gives up on it, which is one of the two ways a case reaches a human.
select public.apply_dispute_event('dd000000-0000-0000-0000-000000000003', 'submit_for_ai');
select public.apply_dispute_event('dd000000-0000-0000-0000-000000000003', 'escalate');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000003') = 'escalated',
  'a case the model gave up on lands in escalated');

\echo ''
\echo '-- who may act --'

set role authenticated;

-- A party is not a reviewer, however much of the case they can see.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.expect_error(
  $q$ select public.claim_dispute('dd000000-0000-0000-0000-000000000003') $q$,
  'a party to the dispute cannot claim it as a reviewer');

select pg_temp.expect_error(
  $q$ select public.issue_human_resolution(
        'dd000000-0000-0000-0000-000000000003', 'refund_to_buyer',
        'I decide in my own favour.', 0, 80000) $q$,
  'a party cannot write the resolution of their own dispute');

-- Someone with no relationship to anything is likewise refused.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ select public.claim_dispute('dd000000-0000-0000-0000-000000000003') $q$,
  'a stranger cannot claim a case');

\echo ''
\echo '-- what a reviewer sees, and what they do not --'

select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);

select pg_temp.check(
  exists (select 1 from public.disputes where id = 'dd000000-0000-0000-0000-000000000003'),
  'a reviewer sees a case that needs a human');

select pg_temp.check(
  not exists (select 1 from public.disputes where id = 'dd000000-0000-0000-0000-000000000002'),
  'a reviewer does not see a case still between the parties');

select pg_temp.check(
  exists (select 1 from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000004'),
  'a reviewer sees the contract under the case');

select pg_temp.check(
  not exists (select 1 from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'a reviewer sees no contract that never reached them');

select pg_temp.check(
  exists (select 1 from public.evidence where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000004'),
  'a reviewer reads the evidence on the case');

-- The other half, and the one that matters. An unqualified column in the
-- policy's subquery makes this comparison always true, and a reviewer then
-- reads every document in the system the moment any case is reviewable.
select pg_temp.check(
  not exists (select 1 from public.evidence where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'a reviewer reads no evidence from a contract that never reached them (saw ' ||
  coalesce((select string_agg(filename, ', ') from public.evidence
            where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'nothing') || ')');

select pg_temp.check(
  not exists (select 1 from public.transaction_events
              where transaction_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'a reviewer reads no history from a contract that never reached them');

-- The deliberate blindness: roles yes, names no.
select pg_temp.check(
  (select count(*) from public.visible_profiles) = 1,
  'a reviewer sees no party name, only their own row (saw ' ||
  coalesce((select string_agg(coalesce(full_name, id::text), ', ') from public.visible_profiles), 'nothing') || ')');

select pg_temp.check(
  (select opened_by_role from public.disputes
   where id = 'dd000000-0000-0000-0000-000000000003') = 'buyer',
  'a reviewer still knows which side opened the case');

\echo ''
\echo '-- claiming --'

select public.claim_dispute('dd000000-0000-0000-0000-000000000003');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000003') = 'human_review',
  'claiming moves the case into human_review');

select pg_temp.check(
  (select reviewer_id from public.disputes
   where id = 'dd000000-0000-0000-0000-000000000003') = '44444444-4444-4444-4444-444444444444',
  'the case records who is holding it');

-- A second reviewer arriving at the same case is refused by the transition
-- table: assign_reviewer is legal only from escalated.
select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
select pg_temp.expect_error(
  $q$ select public.claim_dispute('dd000000-0000-0000-0000-000000000003') $q$,
  'a second reviewer cannot take a case someone already holds');

select pg_temp.expect_error(
  $q$ select public.issue_human_resolution(
        'dd000000-0000-0000-0000-000000000003', 'refund_to_buyer',
        'Deciding a case I never picked up.', 0, 80000) $q$,
  'a reviewer cannot decide a case held by someone else');

\echo ''
\echo '-- the decision --'

select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);

-- The allocation rules apply to a human exactly as they do to the model.
select pg_temp.expect_error(
  $q$ select public.issue_human_resolution(
        'dd000000-0000-0000-0000-000000000003', 'split',
        'One fil short.', 40000, 39999) $q$,
  'a human allocation that does not add up is refused');

select pg_temp.expect_error(
  $q$ select public.issue_human_resolution(
        'dd000000-0000-0000-0000-000000000003', 'refund_to_buyer',
        'A decision that contradicts its own numbers.', 40000, 40000) $q$,
  'a human decision contradicting its own split is refused');

-- A finding a human writes is grounded like any other.
select pg_temp.expect_deferred_error(
  $q$ select public.issue_human_resolution(
        'dd000000-0000-0000-0000-000000000003', 'split',
        'Partly delivered.', 40000, 40000,
        '[{"statement":"They seemed careless.","evidenceIds":[]}]'::jsonb) $q$,
  'a human finding citing no evidence is refused');

select pg_temp.check(
  (select count(*) from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000003') = 0,
  'a refused decision leaves no proposal behind');

-- The real one.
do $$
declare
  v_id uuid;
begin
  v_id := public.issue_human_resolution(
    'dd000000-0000-0000-0000-000000000003', 'split',
    'Twenty two of forty photographs were delivered, and the shoot was cut '
    'short by a cancellation neither side fully owns. The fee is split in '
    'proportion to the work delivered.',
    44000, 36000,
    '[{"statement":"The brief specified forty photographs in ten days.",
       "evidenceIds":["ee000000-0000-0000-0000-000000000020"]}]'::jsonb);
  set constraints all immediate;
  perform pg_temp.check(v_id is not null, 'issue_human_resolution returns the proposal id');
end
$$;

reset role;

select pg_temp.check(
  (select source from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000003') = 'human',
  'the resolution is recorded as a human one');

select pg_temp.check(
  (select model_id is null and confidence is null from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000003'),
  'a human decision carries no model id and no confidence, so it cannot pass for the model''s');

select pg_temp.check(
  (select seller_amount_fils + buyer_amount_fils from public.resolution_proposals
   where dispute_id = 'dd000000-0000-0000-0000-000000000003') = 80000,
  'the human split conserves the disputed amount');

select pg_temp.check(
  (select state from public.disputes where id = 'dd000000-0000-0000-0000-000000000003') = 'resolved_by_human',
  'the case closes without asking the parties to accept, because the reviewer is the escalation');

select pg_temp.check(
  (select state from public.transactions where id = 'aaaaaaaa-0000-0000-0000-000000000004') = 'resolved',
  'closing the case resolves the contract with it');

select pg_temp.check(
  (select actor from public.dispute_events
   where dispute_id = 'dd000000-0000-0000-0000-000000000003'
   order by occurred_at desc, id desc limit 1) = 'system',
  'the closing transition is recorded as a system action');

\echo ''
\echo '-- the reviewer list is not a client table --'

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.reviewers', 'SELECT'),
  'a signed-in user cannot read who the reviewers are');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.reviewers', 'INSERT'),
  'a signed-in user cannot make themselves a reviewer');

select pg_temp.check(
  not has_function_privilege('anon', 'public.claim_dispute(uuid)', 'EXECUTE'),
  'anon holds no grant on claim_dispute');

select pg_temp.check(
  not has_function_privilege('anon',
    'public.issue_human_resolution(uuid, public.resolution_decision, text, bigint, bigint, jsonb)',
    'EXECUTE'),
  'anon holds no grant on issue_human_resolution');


\echo ''
\echo '== Manual verification =='

-- Until UAE Pass is connected, nothing could verify anybody, and the gate
-- above meant a real person could sign up and then get no further. These
-- checks are about the bridge: that it opens the gate, that it says what it
-- is worth, and that it cannot be walked over by whoever it is about.

select pg_temp.check(
  (select identity_verified_at is null from public.profiles
   where id = '33333333-3333-3333-3333-333333333333'),
  'the third party is still unverified, so the gate below is a real gate');

set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);

select pg_temp.expect_error(
  $q$ select public.record_manual_verification(
        '33333333-3333-3333-3333-333333333333',
        'I looked at my own documents and they seemed fine') $q$,
  'a signed-in user cannot verify anybody, including themselves');

reset role;

-- The same call as the table owner, where grants do not apply. What refuses it
-- now is the auth.uid() guard inside the function rather than a missing
-- EXECUTE, which is the half that would still hold if a grant slipped.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ select public.record_manual_verification(
        '33333333-3333-3333-3333-333333333333',
        'I looked at my own documents and they seemed fine') $q$,
  'the function refuses a user session even where grants would have allowed it');
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.expect_error(
  $q$ select public.record_manual_verification(
        '33333333-3333-3333-3333-333333333333', 'ok') $q$,
  'a note too short to say anything is refused');

select pg_temp.expect_error(
  $q$ select public.record_manual_verification(
        '99999999-9999-9999-9999-999999999999',
        'Emirates ID checked over video call, name and photo match') $q$,
  'verifying a profile that does not exist is refused rather than recorded');

select public.record_manual_verification(
  '33333333-3333-3333-3333-333333333333',
  'Emirates ID shown over video call, name and photo match the account');

select pg_temp.check(
  (select identity_verified_at is not null from public.profiles
   where id = '33333333-3333-3333-3333-333333333333'),
  'a manual check verifies the profile');

select pg_temp.check(
  (select identity_provider from public.profiles
   where id = '33333333-3333-3333-3333-333333333333') = 'manual_review',
  'the profile is stamped manual_review, so nobody later mistakes it for UAE Pass');

select pg_temp.check(
  (select count(*) from app.identity_checks
   where user_id = '33333333-3333-3333-3333-333333333333' and outcome = 'verified') = 1,
  'the check itself is recorded, not just its result');

select pg_temp.check(
  (select note from app.identity_checks
   where user_id = '33333333-3333-3333-3333-333333333333') like 'Emirates ID shown%',
  'the record keeps what was actually looked at');

select pg_temp.expect_error(
  $q$ update app.identity_checks set note = 'something else'
      where user_id = '33333333-3333-3333-3333-333333333333' $q$,
  'a recorded check cannot be edited, even by the owner of the table');

select pg_temp.expect_error(
  $q$ delete from app.identity_checks
      where user_id = '33333333-3333-3333-3333-333333333333' $q$,
  'a recorded check cannot be deleted, even by the owner of the table');

-- The contract from the identity gate section, which no one could accept.
set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-000000000002', 'accept');
reset role;
-- reset role does not clear the claim, and the guard below reads auth.uid()
-- rather than the role. Leaving it set makes the next call a user session.
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-000000000002') = 'active',
  'the contract that was refused for an unverified party can now be accepted');

\echo ''
\echo '-- taking a verification back --'

select public.revoke_verification(
  '33333333-3333-3333-3333-333333333333',
  'The ID turned out to belong to somebody else');

select pg_temp.check(
  (select identity_verified_at is null and identity_provider is null
   from public.profiles where id = '33333333-3333-3333-3333-333333333333'),
  'revoking clears both the timestamp and the provider');

select pg_temp.check(
  (select count(*) from app.identity_checks
   where user_id = '33333333-3333-3333-3333-333333333333') = 2,
  'both decisions stay on the record, not only the current one');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-000000000002') = 'active',
  'a contract accepted while both parties were verified stays accepted');

\echo ''
\echo '-- verification is not a client operation --'

select pg_temp.check(
  not has_function_privilege('authenticated',
    'public.record_manual_verification(uuid, text)', 'EXECUTE'),
  'a signed-in user holds no grant on record_manual_verification');

select pg_temp.check(
  not has_function_privilege('anon',
    'public.record_manual_verification(uuid, text)', 'EXECUTE'),
  'anon holds no grant on record_manual_verification');

select pg_temp.check(
  not has_function_privilege('authenticated',
    'public.revoke_verification(uuid, text)', 'EXECUTE'),
  'a signed-in user holds no grant on revoke_verification');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.identity_checks', 'SELECT'),
  'a signed-in user cannot read who was verified and on what basis');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.identity_checks', 'INSERT'),
  'a signed-in user cannot add a check of their own');


\echo ''
\echo '== System functions are not a client API =='

-- The publishable key ships inside the mobile app, so anything anon can call
-- is a public endpoint whether or not it was meant to be one. This sweep is
-- the assertion that matters: it covers functions written after it, which the
-- named checks below cannot.

do $$
declare
  v_reachable text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
  into v_reachable
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    -- Extension members are not ours. A real project installs pgcrypto into
    -- `extensions`; a bare container puts it in `public`, and revoking its
    -- grants would be fighting the platform over functions we never wrote.
    and not exists (
      select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
    );

  perform pg_temp.check(v_reachable is null,
    'no function in public is callable with the key that ships in the app' ||
    coalesce(' (reachable: ' || v_reachable || ')', ''));
end
$$;

-- What a signed-in person does still need. A sweep that revoked too much would
-- pass every check above and break the app, so both directions are pinned.
select pg_temp.check(
  has_function_privilege('authenticated', 'public.apply_transaction_event(uuid, public.transaction_event)', 'EXECUTE'),
  'a signed-in party can still move a contract along');

select pg_temp.check(
  has_function_privilege('authenticated', 'public.accept_resolution_proposal(uuid)', 'EXECUTE'),
  'a signed-in party can still accept a proposal');

select pg_temp.check(
  has_function_privilege('authenticated', 'public.claim_dispute(uuid)', 'EXECUTE'),
  'a reviewer is a signed-in person and can still claim a case');

\echo ''
\echo '-- the guard, not only the grant --'

-- Run as the owner, where grants do not apply, so what answers is the check
-- inside the function. An anon caller was the hole: the old guard asked
-- whether the caller was a signed-in user, and an anonymous one is not.
select set_config('request.jwt.claims', '{"role":"anon"}', false);

select pg_temp.expect_error(
  $q$ select public.record_manual_verification(
        '33333333-3333-3333-3333-333333333333',
        'called with nothing but the key that ships in the app') $q$,
  'the anon role is refused by name, not left to fall through a check for user sessions');

select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
select pg_temp.expect_error(
  $q$ select public.revoke_verification(
        '33333333-3333-3333-3333-333333333333', 'called from a signed-in client') $q$,
  'the authenticated role is refused the same way');

select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select public.record_manual_verification(
  '33333333-3333-3333-3333-333333333333',
  'called by the server, which is the one caller this is for');

select pg_temp.check(
  (select identity_verified_at is not null from public.profiles
   where id = '33333333-3333-3333-3333-333333333333'),
  'the server itself still passes the guard');

select set_config('request.jwt.claims', '', false);


\echo ''
\echo '== Inviting somebody who has no account =='

-- Nothing about the transactions table changes for this. The draft waits in
-- app.contract_invitations, and a transaction appears only when there are two
-- real people to hang it on, so everything downstream is an ordinary contract.

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select pg_temp.expect_error(
  $q$ select public.invite_counterparty('ahmed@startup.ae', 'seller', 'Nope', 'Terms.', 10000) $q$,
  'inviting your own address is refused');

select pg_temp.expect_error(
  $q$ select public.invite_counterparty('sara@design.ae', 'seller', 'Nope', 'Terms.', 10000) $q$,
  'inviting somebody who already has an account is refused, rather than making a code they never need');

-- select * from f(...), not (f(...)).*, which evaluates a volatile function
-- once per output column and would create fourteen invitations here.
create temporary table invite_under_test as
select * from public.invite_counterparty(
  'newcomer@example.ae', 'seller',
  'Arabic copy for a landing page',
  'Six sections, delivered within five days. One round of revision.',
  75000
);

select pg_temp.check(
  (select code ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}$' from invite_under_test),
  'the code is readable down a phone: no vowels, no zero or one');

select pg_temp.check(
  (select transaction_id is null and claimed_at is null from invite_under_test),
  'no transaction exists yet, because there is still only one person');

select pg_temp.check(
  (select count(*)::int from public.my_invitations()) = 1,
  'the inviter can see what they sent');

reset role;

\echo ''
\echo '-- the code is not a bearer token --'

-- The person it was addressed to now signs up. Created after the invitation
-- on purpose: invite_counterparty refuses an address that already has one.
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666', 'newcomer@example.ae');
insert into public.profiles (id, full_name, email) values
  ('66666666-6666-6666-6666-666666666666', 'Newcomer', 'newcomer@example.ae');

set role authenticated;

-- Somebody else holding the right code. This is the case a code alone would
-- have let through: taking the other side of a contract meant for a stranger.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  format($q$ select public.claim_invitation(%L) $q$, (select code from invite_under_test)),
  'the wrong person cannot claim a code that is not addressed to them');

select pg_temp.expect_error(
  $q$ select public.claim_invitation('ZZZZ-ZZZZ') $q$,
  'a code that does not exist gets the same answer as one that is not yours, so this is not a way to hunt for live invitations');

select set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', false);

create temporary table claimed_txn as
select public.claim_invitation((select code from invite_under_test)) as id;

select pg_temp.check(
  (select state from public.transactions where id = (select id from claimed_txn))
    = 'pending_acceptance',
  'claiming sends the contract rather than leaving it drafted: the inviter already did their part');

select pg_temp.check(
  (select seller_id from public.transactions where id = (select id from claimed_txn))
    = '66666666-6666-6666-6666-666666666666',
  'the invitee lands on the side the invitation named');

select pg_temp.check(
  (select created_by from public.transactions where id = (select id from claimed_txn))
    = '11111111-1111-1111-1111-111111111111',
  'the contract records the inviter as its author, which is who wrote the terms');

select pg_temp.expect_error(
  format($q$ select public.claim_invitation(%L) $q$, (select code from invite_under_test)),
  'a code works once');

reset role;

\echo ''
\echo '-- withdrawing, and running out of time --'

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select pg_temp.expect_error(
  format($q$ select public.revoke_invitation(%L) $q$, (select id from invite_under_test)),
  'an invitation that became a contract cannot be withdrawn, because withdrawing it would not undo the contract');

create temporary table second_invite as
select * from public.invite_counterparty(
  'later@example.ae', 'buyer', 'Something else', 'Terms.', 20000
);

select public.revoke_invitation((select id from second_invite));

reset role;
insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777', 'later@example.ae');
insert into public.profiles (id, full_name, email) values
  ('77777777-7777-7777-7777-777777777777', 'Later', 'later@example.ae');

set role authenticated;
select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777777', false);
select pg_temp.expect_error(
  format($q$ select public.claim_invitation(%L) $q$, (select code from second_invite)),
  'a withdrawn invitation cannot be claimed');

reset role;

-- Expiry, forced rather than waited for.
update app.contract_invitations
set revoked_at = null, expires_at = now() - interval '1 day'
where id = (select id from second_invite);

set role authenticated;
select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777777', false);
select pg_temp.expect_error(
  format($q$ select public.claim_invitation(%L) $q$, (select code from second_invite)),
  'an expired invitation cannot be claimed');

select pg_temp.check(
  (select count(*)::int from public.my_invitations()) = 0,
  'somebody who has sent nothing sees nothing, including invitations addressed to them');

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '-- the invitation list is not a client table --'

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.contract_invitations', 'SELECT'),
  'a signed-in user cannot read the addresses other people have invited');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.contract_invitations', 'INSERT'),
  'a signed-in user cannot write an invitation directly, bypassing the checks');

select pg_temp.check(
  not has_function_privilege('authenticated', 'app.new_invitation_code()', 'EXECUTE'),
  'a signed-in user cannot mint codes on their own');


\echo ''
\echo '== Telling somebody that something needs them =='

-- A fresh contract between two known parties, so every count below is about
-- this one and not about everything the suite has driven so far.

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-0000000000ff',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'Contract used for the notification checks',
   'Terms.', 30000,
   '11111111-1111-1111-1111-111111111111');

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000ff', 'submit');
reset role;

select pg_temp.check(
  (select count(*)::int from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '22222222-2222-2222-2222-222222222222') = 1,
  'sending a contract tells the other party');

select pg_temp.check(
  (select count(*)::int from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '11111111-1111-1111-1111-111111111111') = 0,
  'and does not tell the person who sent it, who already knows');

select pg_temp.check(
  (select needs_you from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '22222222-2222-2222-2222-222222222222'),
  'a contract waiting to be accepted is marked as needing them, not as news');

select pg_temp.check(
  (select source = 'transaction' and event = 'submit' and actor = 'buyer'
   from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '22222222-2222-2222-2222-222222222222'),
  'the row carries the event, its machine and who acted, never a sentence to read out');

set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000ff', 'accept');
reset role;

select pg_temp.check(
  (select count(*)::int from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '11111111-1111-1111-1111-111111111111'
     and n.event = 'accept') = 1,
  'accepting tells the other side in turn');

-- The case the live check caught and this suite had not thought to ask about.
select pg_temp.check(
  (select not needs_you from app.notifications n
   where n.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
     and n.recipient_id = '11111111-1111-1111-1111-111111111111'
     and n.event = 'accept'),
  'being told your contract was accepted is news: the work is now the other side''s');

select pg_temp.check(
  app.transaction_event_needs_them('request_revision'),
  'asking for changes is a job of work for whoever is told, not a comment');

\echo ''
\echo '-- what each person can see --'

set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select pg_temp.check(
  not exists (
    select 1 from public.my_notifications(200) m
    where m.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
      and m.event = 'accept'),
  'your own move is not in your own list');

select pg_temp.check(
  exists (
    select 1 from public.my_notifications(200) m
    where m.transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000ff'
      and m.event = 'submit'),
  'the move that is waiting on you is');

select pg_temp.check(
  (select count(*)::int from public.my_notifications(3)) <= 3,
  'the limit is honoured, so a long history cannot be asked for in one call');

-- Marking read takes a cutoff, so opening the list marks what was on screen
-- rather than something that landed while it was being read.
select pg_temp.check(
  public.mark_notifications_read(now() - interval '1 hour') = 0,
  'nothing older than the cutoff means nothing marked');

select pg_temp.check(
  public.mark_notifications_read() > 0,
  'without a cutoff, everything unread is marked');

select pg_temp.check(
  public.mark_notifications_read() = 0,
  'and marking twice marks nothing the second time');

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '-- the outbox is not a client table --'

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.notifications', 'SELECT'),
  'a signed-in user cannot read who is being told what');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.notifications', 'UPDATE'),
  'nor mark somebody else''s as read');

select pg_temp.check(
  not has_function_privilege('anon', 'public.my_notifications(integer)', 'EXECUTE'),
  'anon holds no grant on the list');

-- Delivery state is writable on purpose, unlike everything else this schema
-- keeps. A notification is a job about the record, not part of it.
select pg_temp.check(
  not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'app.notifications'::regclass
      and not t.tgisinternal
      and t.tgfoid = 'app.forbid_mutation'::regproc),
  'the outbox is deliberately not append-only: read and sent have to be writable');


\echo ''
\echo '== Handing the outbox to something that sends =='

-- Two people who exist only for this section, and one contract between them.
-- The pair above will not do: the section before this one marked everything
-- of theirs read, and read rows are deliberately never mailed.

insert into auth.users (id, email) values
  ('88888888-8888-8888-8888-888888888888', 'mailed.buyer@example.ae'),
  ('99999999-9999-9999-9999-999999999999', 'mailed.seller@example.ae');

insert into public.profiles (id, full_name, email, identity_verified_at, identity_provider) values
  ('88888888-8888-8888-8888-888888888888', 'Mailed Buyer',  'mailed.buyer@example.ae',  now(), 'manual_review'),
  ('99999999-9999-9999-9999-999999999999', 'Mailed Seller', 'mailed.seller@example.ae', now(), 'manual_review');

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-0000000000ee',
   '88888888-8888-8888-8888-888888888888',
   '99999999-9999-9999-9999-999999999999',
   'Contract used for the delivery checks',
   'Terms.', 40000,
   '88888888-8888-8888-8888-888888888888');

set role authenticated;
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000ee', 'submit');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select count(*)::int from public.notifications_to_send('0 seconds'::interval)) > 0,
  'with no grace period there is something to send');

select pg_temp.check(
  (select count(*)::int from public.notifications_to_send('1 hour'::interval)) = 0,
  'and with an hour of grace there is not, so two moves in a row become one email');

select pg_temp.check(
  (select waiting from public.notifications_to_send('0 seconds'::interval) w
   where w.recipient_id = '99999999-9999-9999-9999-999999999999') = 1,
  'one row per person carrying a count, not one row per event');

select pg_temp.check(
  (select locale from public.notifications_to_send('0 seconds'::interval) w
   where w.recipient_id = '99999999-9999-9999-9999-999999999999') = 'en',
  'somebody who never chose a language is written to in English');

set role authenticated;
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', false);
select public.set_preferred_locale('ar');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select locale from public.notifications_to_send('0 seconds'::interval) w
   where w.recipient_id = '99999999-9999-9999-9999-999999999999') = 'ar',
  'and somebody who chose Arabic is written to in Arabic');

-- Inside a session on purpose. Run with the claim cleared, this passed on
-- "sign in first" and proved nothing about the language at all.
set role authenticated;
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', false);

select pg_temp.expect_error(
  $q$ select public.set_preferred_locale('fr') $q$,
  'a language the app does not speak is refused rather than stored');

select pg_temp.check(
  (select preferred_locale from public.profiles
   where id = '99999999-9999-9999-9999-999999999999') = 'ar',
  'and the refusal left the previous choice standing');

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- Marking, both ways round.
do $$
declare
  v_ids bigint[];
begin
  select ids into v_ids
  from public.notifications_to_send('0 seconds'::interval) w
  where w.recipient_id = '99999999-9999-9999-9999-999999999999';

  perform public.mark_notifications_sent(v_ids, 'brevo 500');
  perform pg_temp.check(
    (select count(*)::int from public.notifications_to_send('0 seconds'::interval) w
     where w.recipient_id = '99999999-9999-9999-9999-999999999999') = 0,
    'a batch that failed is not offered again, so nobody is retried at forever');

  perform pg_temp.check(
    (select email_error is not null and emailed_at is null
     from app.notifications where id = v_ids[1]),
    'and the failure is written down rather than swallowed');
end
$$;

\echo ''
\echo '-- addresses that can never receive anything --'

-- The seed and verification scripts use @example.test throughout. Every one
-- of those would be accepted by the provider, bounce, and count against the
-- reputation the real mail depends on. RFC 2606 reserves the label, so this
-- is a fact about the address rather than a guess about the mailbox.
insert into auth.users (id, email) values
  ('aaaa0000-0000-0000-0000-00000000aaaa', 'seeded@example.test');
insert into public.profiles (id, full_name, email, identity_verified_at, identity_provider) values
  ('aaaa0000-0000-0000-0000-00000000aaaa', 'Seeded Person', 'seeded@example.test', now(), 'manual_review');

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-0000000000dd',
   '88888888-8888-8888-8888-888888888888',
   'aaaa0000-0000-0000-0000-00000000aaaa',
   'Contract with a seeded address',
   'Terms.', 12000,
   '88888888-8888-8888-8888-888888888888');

set role authenticated;
select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000dd', 'submit');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select count(*)::int from app.notifications n
   where n.recipient_id = 'aaaa0000-0000-0000-0000-00000000aaaa') = 1,
  'a seeded person still gets the notification in the app');

select pg_temp.check(
  (select count(*)::int from public.notifications_to_send('0 seconds'::interval) w
   where w.recipient_id = 'aaaa0000-0000-0000-0000-00000000aaaa') = 0,
  'but nothing is ever mailed to a reserved domain, because it can only bounce');

select pg_temp.check(
  (select count(*)::int from public.notifications_to_send('0 seconds'::interval) w
   where w.email like '%@example.ae') >= 0,
  'and a real top level domain is not caught by the same rule');

\echo ''
\echo '-- who may drain it --'

select pg_temp.check(
  not has_function_privilege('authenticated', 'public.notifications_to_send(interval)', 'EXECUTE'),
  'a signed-in user cannot read who is about to be written to');

select pg_temp.check(
  not has_function_privilege('authenticated', 'public.mark_notifications_sent(bigint[], text)', 'EXECUTE'),
  'nor mark somebody else''s mail as sent');

select pg_temp.check(
  has_function_privilege('service_role', 'public.notifications_to_send(interval)', 'EXECUTE'),
  'the sender, which holds the service role, can');

select pg_temp.check(
  has_function_privilege('authenticated', 'public.set_preferred_locale(text)', 'EXECUTE'),
  'choosing your own language is yours to do');


\echo ''
\echo '== Work agreed a stage at a time =='

-- A contract in two stages between the two verified fixtures.

insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('aaaaaaaa-0000-0000-0000-0000000000cc',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'Two stage build',
   'Design, then build.', 100000,
   '11111111-1111-1111-1111-111111111111');

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

insert into public.milestones (id, transaction_id, position, title, amount_fils) values
  ('bbbbbbbb-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000cc', 0, 'Design', 40000),
  ('bbbbbbbb-0000-0000-0000-0000000000c2', 'aaaaaaaa-0000-0000-0000-0000000000cc', 1, 'Build',  60000);

select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000cc', 'submit');
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.apply_transaction_event('aaaaaaaa-0000-0000-0000-0000000000cc', 'accept');

select pg_temp.expect_error(
  $q$ insert into public.milestones (transaction_id, position, title, amount_fils)
      values ('aaaaaaaa-0000-0000-0000-0000000000cc', 2, 'Snuck in later', 1000) $q$,
  'stages cannot be added once the contract is live, so the plan is what was agreed');

\echo ''
\echo '-- delivering and accepting --'

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select pg_temp.expect_error(
  $q$ select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c1') $q$,
  'the buyer cannot deliver a stage');

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select pg_temp.expect_error(
  $q$ select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c1') $q$,
  'somebody outside the contract gets the same answer as for an id that does not exist');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c1');

select pg_temp.check(
  (select delivered_at is not null from public.milestones
   where id = 'bbbbbbbb-0000-0000-0000-0000000000c1'),
  'the seller delivers the first stage');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-0000000000cc') = 'active',
  'and the contract stays active, because one stage of two is not the work');

select pg_temp.expect_error(
  $q$ select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c1') $q$,
  'a stage cannot be delivered twice');

reset role;
select pg_temp.check(
  (select count(*)::int from app.notifications n
   where n.milestone_id = 'bbbbbbbb-0000-0000-0000-0000000000c1'
     and n.recipient_id = '11111111-1111-1111-1111-111111111111'
     and n.source = 'milestone' and n.needs_you) = 1,
  'the buyer is told, and told that it is their turn to look');

set role authenticated;

\echo ''
\echo '-- sending one back --'

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.request_milestone_revision('bbbbbbbb-0000-0000-0000-0000000000c1');

select pg_temp.check(
  (select delivered_at is null from public.milestones
   where id = 'bbbbbbbb-0000-0000-0000-0000000000c1'),
  'a stage sent back is genuinely not delivered any more');

select pg_temp.check(
  (select count(*)::int from public.milestone_events
   where milestone_id = 'bbbbbbbb-0000-0000-0000-0000000000c1') = 2,
  'but the attempt is not erased: the round trip is two entries');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c1');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.accept_milestone('bbbbbbbb-0000-0000-0000-0000000000c1');

select pg_temp.check(
  (select accepted_at is not null from public.milestones
   where id = 'bbbbbbbb-0000-0000-0000-0000000000c1'),
  'the second attempt is accepted');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-0000000000cc') = 'active',
  'and one stage accepted does not finish a two stage contract');

\echo ''
\echo '-- the last stage carries the contract --'

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c2');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-0000000000cc') = 'delivered',
  'the last stage delivered is the work delivered');

select pg_temp.check(
  (select actor from public.transaction_events
   where transaction_id = 'aaaaaaaa-0000-0000-0000-0000000000cc'
   order by occurred_at desc, id desc limit 1) = 'seller',
  'recorded as the seller, who did it, and not as TrustIQ');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.request_milestone_revision('bbbbbbbb-0000-0000-0000-0000000000c2');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-0000000000cc') = 'active',
  'sending the last stage back brings the whole contract back with it');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.deliver_milestone('bbbbbbbb-0000-0000-0000-0000000000c2');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.accept_milestone('bbbbbbbb-0000-0000-0000-0000000000c2');

select pg_temp.check(
  (select state from public.transactions
   where id = 'aaaaaaaa-0000-0000-0000-0000000000cc') = 'completed',
  'accepting the last stage completes the contract, without asking for the same signature twice');

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '-- the stage record cannot be rewritten --'

select pg_temp.expect_error(
  $q$ update public.milestone_events set event = 'accept'
      where milestone_id = 'bbbbbbbb-0000-0000-0000-0000000000c1' $q$,
  'a stage move cannot be edited, even by the owner of the table');

select pg_temp.check(
  not has_function_privilege('anon', 'public.deliver_milestone(uuid)', 'EXECUTE'),
  'anon holds no grant on delivering a stage');

select pg_temp.check(
  not has_function_privilege('authenticated', 'app.milestone_context(uuid)', 'EXECUTE'),
  'and the helper that resolves your role is not a client function');


\echo ''
\echo '== Leaving =='

-- Somebody who signed up and did nothing, and somebody who is on a contract.
-- The two are owed different things and the difference is decided by the data.

insert into auth.users (id, email) values
  ('cccc0000-0000-0000-0000-00000000cccc', 'passing.through@example.ae');
insert into public.profiles (id, full_name, email) values
  ('cccc0000-0000-0000-0000-00000000cccc', 'Passing Through', 'passing.through@example.ae');

select pg_temp.check(
  (select outcome from public.close_account('cccc0000-0000-0000-0000-00000000cccc')) = 'deleted',
  'somebody nothing points at is genuinely deleted, not given a tombstone');

select pg_temp.check(
  not exists (select 1 from public.profiles where id = 'cccc0000-0000-0000-0000-00000000cccc'),
  'and the row is gone');

select pg_temp.check(
  (select email from app.deletion_requests
   where user_id = 'cccc0000-0000-0000-0000-00000000cccc') = 'passing.through@example.ae',
  'the request is on record with the address, so a later question can be answered');

\echo ''
\echo '-- somebody a contract points at --'

select pg_temp.check(
  (select outcome from public.close_account('22222222-2222-2222-2222-222222222222')) = 'anonymised',
  'somebody on a contract is emptied rather than removed');

select pg_temp.check(
  (select full_name from public.profiles
   where id = '22222222-2222-2222-2222-222222222222') = 'Closed account',
  'the name goes');

select pg_temp.check(
  (select email from public.profiles
   where id = '22222222-2222-2222-2222-222222222222') like '%@deleted.invalid',
  'and the address becomes one that can never be delivered to');

select pg_temp.check(
  (select identity_verified_at is null and identity_provider is null
   from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'the verification goes with the person: nobody is left vouched for by nobody');

select pg_temp.check(
  (select kept from app.deletion_requests
   where user_id = '22222222-2222-2222-2222-222222222222') like '%contracts you were party to%',
  'and what was kept is written down in words, not left to be reconstructed');

\echo ''
\echo '-- what the other party keeps --'

select pg_temp.check(
  exists (select 1 from public.transactions
          where seller_id = '22222222-2222-2222-2222-222222222222'),
  'the contracts are still there, because they are the other party''s too');

select pg_temp.check(
  exists (select 1 from public.evidence
          where uploaded_by = '22222222-2222-2222-2222-222222222222'),
  'so are the documents that were filed against them');

-- The synergy worth pinning: the tombstone domain is one the sender already
-- refuses, so nothing has to remember not to write to a closed account.
select pg_temp.check(
  (select count(*)::int from public.notifications_to_send('0 seconds'::interval) w
   where w.recipient_id = '22222222-2222-2222-2222-222222222222') = 0,
  'and no mail will ever go to the tombstone, because it is a reserved domain');

\echo ''
\echo '-- who may close an account --'

select pg_temp.check(
  not has_function_privilege('authenticated', 'public.close_account(uuid)', 'EXECUTE'),
  'a signed-in user cannot close an account directly, not even their own');

select pg_temp.check(
  not has_function_privilege('anon', 'public.close_account(uuid)', 'EXECUTE'),
  'and anon certainly cannot close somebody else''s');

select pg_temp.expect_error(
  $q$ update app.deletion_requests set outcome = 'deleted'
      where user_id = '22222222-2222-2222-2222-222222222222' $q$,
  'the record of a closure cannot be edited afterwards');

\echo ''
\echo '== The operator sees numbers, not people =='

reset role;

insert into auth.users (id, email) values
  ('0f000000-0000-0000-0000-000000000001', 'operator@trustiq.ae'),
  ('0f000000-0000-0000-0000-000000000002', 'curious@example.ae'),
  ('0f000000-0000-0000-0000-000000000003', 'leaver@example.ae');

insert into public.profiles (id, full_name, email) values
  ('0f000000-0000-0000-0000-000000000001', 'The Operator',   'operator@trustiq.ae'),
  ('0f000000-0000-0000-0000-000000000002', 'Curious Person', 'curious@example.ae'),
  ('0f000000-0000-0000-0000-000000000003', 'Just Looking',   'leaver@example.ae');

-- Signing in is not being an operator. Checked before the row is added, so the
-- refusal is the default rather than something that has to be arranged.
set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000001', false);

select pg_temp.expect_error(
  $q$ select * from public.admin_overview() $q$,
  'a signed-in person who is not on the list is refused the overview');

reset role;
insert into app.admins (user_id, note) values
  ('0f000000-0000-0000-0000-000000000001', 'Added by the schema tests');

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000001', false);

select pg_temp.check(
  (select people from public.admin_overview()) >= 3,
  'once on the list, the same call answers, through the grant the app would use');

-- The rest of the numbers are checked without the role, keeping the operator's
-- identity. The function reads past RLS on purpose; a control query run as
-- `authenticated` does not, because the operator is party to none of these
-- contracts. Comparing the two from inside that role compares the truth
-- against a filtered view of it and fails for a reason that has nothing to do
-- with the function.
reset role;

\echo ''
\echo '-- counted from what happened, not from where things sit now --'

select pg_temp.check(
  (select contracts_binding from public.admin_overview()) =
  (select count(distinct e.transaction_id)
   from public.transaction_events e
   join app.real_transactions t on t.id = e.transaction_id
   where e.event = 'accept'),
  'binding contracts are counted from the event log');

-- Without this, the assertion above would pass even if the function read
-- current state, because nothing would have moved on yet.
select pg_temp.check(
  exists (select 1 from public.transactions t
          join public.transaction_events e on e.transaction_id = t.id and e.event = 'accept'
          where t.state <> 'active'),
  'and at least one accepted contract has since moved on, so the two readings differ');

select pg_temp.check(
  (select proposals_accepted from public.admin_overview()) =
  (select count(*) from (
     select a.proposal_id
     from public.dispute_acceptances a
     join public.resolution_proposals r on r.id = a.proposal_id and r.source = 'ai'
     join public.disputes d on d.id = r.dispute_id
     join app.real_transactions t on t.id = d.transaction_id
     group by a.proposal_id having count(*) = 2) agreed),
  'a proposal counts as accepted only when both parties accepted it');

select pg_temp.check(
  (select coalesce(sum(calls), 0) from public.admin_ai_quality()) =
  (select count(*) from public.ai_call_log),
  'every model run is in the quality breakdown, the failed ones included');

\echo ''
\echo '-- and only about people who exist --'

-- The scripts in scripts/ have filled the live database with accounts at the
-- RFC 2606 domains. Left in, they were most of the headline: 38 profiles of
-- which 6 were somebody. This is the assertion that the panel is about the
-- business rather than about its own test fixtures.

select set_config('trustiq.people_before', (select people from public.admin_overview())::text, false);
select set_config('trustiq.contracts_before', (select contracts from public.admin_overview())::text, false);

insert into auth.users (id, email) values
  ('0f000000-0000-0000-0000-0000000000a1', 'fixture.one@example.test'),
  ('0f000000-0000-0000-0000-0000000000a2', 'fixture.two@nowhere.invalid');
insert into public.profiles (id, full_name, email) values
  ('0f000000-0000-0000-0000-0000000000a1', 'Fixture One', 'fixture.one@example.test'),
  ('0f000000-0000-0000-0000-0000000000a2', 'Fixture Two', 'fixture.two@nowhere.invalid');

select pg_temp.check(
  (select people from public.admin_overview())::text = current_setting('trustiq.people_before'),
  'two accounts at reserved domains do not move the headcount');

-- A contract between them, submitted so it is a live row rather than a draft
-- nobody sent. It stops there: two unverified fixtures cannot make a contract
-- binding, which is a rule from 0002 and not something this test should be
-- working around.
insert into public.transactions
  (id, buyer_id, seller_id, description, terms, total_amount_fils, created_by)
values
  ('0f000000-0000-0000-0000-0000000000b1',
   '0f000000-0000-0000-0000-0000000000a1',
   '0f000000-0000-0000-0000-0000000000a2',
   'A contract between two fixtures',
   'Nothing here was ever agreed by anybody.',
   10000,
   '0f000000-0000-0000-0000-0000000000a1');

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000a1', false);
select public.apply_transaction_event('0f000000-0000-0000-0000-0000000000b1', 'submit');
reset role;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000001', false);

select pg_temp.check(
  (select contracts from public.admin_overview())::text = current_setting('trustiq.contracts_before'),
  'nor does a contract between them, even one that has been sent');

-- And the guard on the guard: the row really is there, so the assertion above
-- is about the filter rather than about an insert that quietly failed.
select pg_temp.check(
  (select state from public.transactions
   where id = '0f000000-0000-0000-0000-0000000000b1') = 'pending_acceptance',
  'the fixture contract exists and is live, it is simply not counted');

\echo ''
\echo '-- the window --'

select pg_temp.check(
  (select count(*) from public.admin_daily(7)) = 7,
  'a seven day window has seven rows, including the days nothing happened');

select pg_temp.check(
  (select count(*) from public.admin_daily(100000)) = 365,
  'an absurd window is clamped rather than refused');

select pg_temp.check(
  (select count(*) from public.admin_daily(0)) = 1,
  'and so is a nonsensical one');

select pg_temp.check(
  (select count(*) from public.admin_daily(null)) = 30,
  'no window at all means thirty days');

select pg_temp.check(
  (select signups from public.admin_daily(1)) >= 3,
  'the profiles this suite just created land on today');

\echo ''
\echo '-- everybody else --'

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000002', false);

select pg_temp.expect_error(
  $q$ select * from public.admin_overview() $q$,
  'another signed-in person cannot read the overview');

select pg_temp.expect_error(
  $q$ select * from public.admin_daily(30) $q$,
  'nor the daily series');

select pg_temp.expect_error(
  $q$ select * from public.admin_ai_quality() $q$,
  'nor how the model has been doing');

select pg_temp.check(
  not has_function_privilege('anon', 'public.admin_overview()', 'EXECUTE'),
  'anon holds no grant on the overview');

select pg_temp.check(
  not has_table_privilege('authenticated', 'app.admins', 'SELECT'),
  'a signed-in person cannot read who the operators are');

\echo ''
\echo '== Attendance =='

-- Still the curious person, who is not an operator: marking yourself present
-- is something everybody does.
select public.record_activity();
select public.record_activity();

-- A signed-in caller with no profile yet. That this line runs at all is the
-- assertion: the function stays quiet instead of raising, because a counter
-- must never be the reason a launch fails.
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000ff', false);
select public.record_activity();

-- Counted without the role. `authenticated` holds no privilege on app.activity
-- at all, which is the sweep further up doing its job: a signed-in person can
-- add themselves to the register and can never read it.
reset role;

select pg_temp.check(
  (select count(*) from app.activity
   where user_id = '0f000000-0000-0000-0000-000000000002') = 1,
  'opening the app twice in a day leaves one row, not two');

select pg_temp.check(
  (select count(*) from app.activity
   where user_id = '0f000000-0000-0000-0000-0000000000ff') = 0,
  'a caller with no profile is not recorded, and is not an error either');

select pg_temp.check(
  has_function_privilege('authenticated', 'public.record_activity()', 'EXECUTE'),
  'a signed-in person can still mark themselves present');

select pg_temp.check(
  not has_function_privilege('anon', 'public.record_activity()', 'EXECUTE'),
  'and nobody can do it without signing in');

\echo ''
\echo '-- attendance is never what keeps an account alive --'

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000003', false);
select public.record_activity();
reset role;

select pg_temp.check(
  (select count(*) from app.activity
   where user_id = '0f000000-0000-0000-0000-000000000003') = 1,
  'somebody who only ever opened the app has an attendance row');

-- Closing is a system action, and app.assert_system_caller refuses any caller
-- carrying a session, whatever role it holds. The suite has been signing
-- people in for two hundred assertions, so the claim has to be put down first.
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select outcome from public.close_account('0f000000-0000-0000-0000-000000000003')) = 'deleted',
  'and is still deleted outright, because attendance is not a record anyone is owed');

select pg_temp.check(
  (select count(*) from app.activity
   where user_id = '0f000000-0000-0000-0000-000000000003') = 0,
  'their attendance went with them');

reset role;

\echo ''
\echo '== Asking to be verified =='

reset role;
select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id, email) values
  ('0f000000-0000-0000-0000-0000000000d1', 'wants.in@example.ae'),
  ('0f000000-0000-0000-0000-0000000000d2', 'turned.down@example.ae');
insert into public.profiles (id, full_name, email) values
  ('0f000000-0000-0000-0000-0000000000d1', 'Wants In',    'wants.in@example.ae'),
  ('0f000000-0000-0000-0000-0000000000d2', 'Turned Down', 'turned.down@example.ae');

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000d1', false);

-- Before asking, and this is the state that did not exist at all: somebody who
-- has never asked looked exactly like somebody whose request was refused.
select pg_temp.check(
  (select standing from public.my_verification()) = 'none',
  'somebody who has never asked is told so, rather than shown nothing');

select public.request_verification('Wants In Al Mansouri', 'emirates_id', 'Happy to come to the office.');

select pg_temp.check(
  (select standing from public.my_verification()) = 'pending',
  'after asking, they are waiting');

select pg_temp.check(
  (select legal_name from public.my_verification()) = 'Wants In Al Mansouri',
  'and the name being checked is the one they gave, not the one on the profile');

select pg_temp.expect_error(
  $q$ select * from public.request_verification('Wants In Al Mansouri', 'passport') $q$,
  'asking twice is refused, so nobody is in the queue twice');

\echo ''
\echo '-- a refusal has to be answerable --'

reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.expect_error(
  $q$ select * from public.decide_verification(
        (select id from app.verification_requests
         where user_id = '0f000000-0000-0000-0000-0000000000d1'), false, 'no') $q$,
  'a refusal with no real reason is refused, because it is a dead end for the person');

\echo ''
\echo '-- deciding is not something a client does --'

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000d1', false);

select pg_temp.check(
  not has_function_privilege('authenticated',
    'public.decide_verification(uuid, boolean, text)', 'EXECUTE'),
  'a signed-in person cannot decide their own verification');

select pg_temp.check(
  not has_function_privilege('authenticated', 'public.verification_queue()', 'EXECUTE'),
  'nor read the queue, which carries names');

select pg_temp.check(
  not has_function_privilege('anon', 'public.request_verification(text, text, text)', 'EXECUTE'),
  'and asking at all needs an account');

\echo ''
\echo '-- the queue --'

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000d2', false);
select public.request_verification('Turned Down Bin Rashid', 'passport');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select count(*) from public.verification_queue()) = 2,
  'both requests are waiting, oldest first');

select pg_temp.check(
  (select email from public.verification_queue() limit 1) = 'wants.in@example.ae',
  'and the one who asked first is at the front');

\echo ''
\echo '-- yes --'

select pg_temp.check(
  (select outcome from public.decide_verification(
     (select id from app.verification_requests
      where user_id = '0f000000-0000-0000-0000-0000000000d1'),
     true,
     'Emirates ID seen in person at the Sharjah office, name and photo match.')) = 'approved',
  'a request can be approved');

select pg_temp.check(
  (select identity_verified_at is not null from public.profiles
   where id = '0f000000-0000-0000-0000-0000000000d1'),
  'and the profile is actually stamped, through the one path that does that');

select pg_temp.check(
  (select provider from (
     select identity_provider as provider from public.profiles
     where id = '0f000000-0000-0000-0000-0000000000d1') x) = 'manual_review',
  'as a manual review, never as UAE Pass');

select pg_temp.check(
  exists (select 1 from app.identity_checks
          where user_id = '0f000000-0000-0000-0000-0000000000d1' and outcome = 'verified'),
  'and what was looked at is on the append-only record');

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000d1', false);

select pg_temp.check(
  (select standing from public.my_verification()) = 'verified',
  'the person is told they are verified');

select pg_temp.expect_error(
  $q$ select * from public.request_verification('Wants In Al Mansouri', 'passport') $q$,
  'and cannot join the queue again');

\echo ''
\echo '-- no, with a reason they can act on --'

reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select outcome from public.decide_verification(
     (select id from app.verification_requests
      where user_id = '0f000000-0000-0000-0000-0000000000d2'),
     false,
     'The passport photo page was cut off. Send one showing all four corners.')) = 'rejected',
  'a request can be refused');

set role authenticated;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-0000000000d2', false);

select pg_temp.check(
  (select standing from public.my_verification()) = 'rejected',
  'the person is told they were refused');

select pg_temp.check(
  (select reason from public.my_verification()) like 'The passport photo page%',
  'and told why, in words they can do something about');

-- The whole point of recording a refusal rather than silently doing nothing.
select public.request_verification('Turned Down Bin Rashid', 'passport', 'Full page this time.');

select pg_temp.check(
  (select standing from public.my_verification()) = 'pending',
  'and can ask again afterwards');

\echo ''
\echo '-- changing your mind --'

select pg_temp.check(
  (select public.withdraw_verification_request()) is true,
  'a waiting request can be withdrawn');

select pg_temp.check(
  (select standing from public.my_verification()) = 'none',
  'and the person is back to never having asked');

select pg_temp.check(
  (select public.withdraw_verification_request()) is false,
  'withdrawing nothing says so rather than raising');

reset role;
select set_config('request.jwt.claim.sub', '', false);

select pg_temp.check(
  (select count(*) from app.verification_requests
   where user_id = '0f000000-0000-0000-0000-0000000000d2') = 2,
  'both attempts stay on the record, the refused one included');

select pg_temp.check(
  (select count(*) from public.verification_queue()) = 0,
  'and nothing is left waiting');

\echo ''
\echo 'ALL SCHEMA TESTS PASSED'
