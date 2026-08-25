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
\echo 'ALL SCHEMA TESTS PASSED'

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
