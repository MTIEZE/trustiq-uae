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

select pg_temp.check(
  not has_table_privilege('anon', 'public.visible_profiles', 'SELECT'),
  'anon cannot read the profile view');

\echo ''
\echo 'ALL SCHEMA TESTS PASSED'
