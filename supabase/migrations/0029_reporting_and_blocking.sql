-- ---------------------------------------------------------------------------
-- Reporting somebody, and refusing to deal with them again.
--
-- Two parties to a contract exchange free text and upload files to each other.
-- That is user-generated content whichever way it is argued, and until now
-- there was no way to report any of it and no way to keep a person from
-- addressing you a second time. Google Play's policy expects both, which is
-- what prompted this; the reason to keep it is that a trust product without a
-- way to say "this person is not acting in good faith" is missing the thing it
-- is named after.
--
-- Blocking here does not mean hiding. You cannot unsee a contract you are
-- already party to, and pretending otherwise would lose evidence somebody may
-- need. It means: this person cannot start anything new with me.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------

create table app.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint block_is_of_somebody_else check (blocker_id <> blocked_id)
);

comment on table app.blocks is
  'One row per person who has refused future contracts from another. Does not affect contracts that already exist.';

create index blocks_blocked_idx on app.blocks (blocked_id);

alter table app.blocks enable row level security;

/** Whether either of these two has refused the other. Direction-blind. */
create or replace function app.is_blocked_between(p_one uuid, p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from app.blocks b
    where (b.blocker_id = p_one and b.blocked_id = p_other)
       or (b.blocker_id = p_other and b.blocked_id = p_one)
  );
$$;

-- ---------------------------------------------------------------------------
-- A block has to actually stop something, in both places a contract can start.
-- ---------------------------------------------------------------------------

create or replace function app.refuse_blocked_contract()
returns trigger
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  if app.is_blocked_between(new.buyer_id, new.seller_id) then
    -- Deliberately does not say which of them blocked which. The refusal is
    -- the same sentence whichever direction it came from, so a contract that
    -- will not open cannot be used to work out that somebody blocked you.
    raise exception 'this contract cannot be opened between these two accounts'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger transactions_refuse_blocked
  before insert on public.transactions
  for each row execute function app.refuse_blocked_contract();

-- The lookup by email answers "no such person" rather than "blocked", for the
-- same reason: an error that distinguishes the two is a way to test whether
-- somebody has blocked you.
create or replace function public.find_counterparty(p_email text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
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

  if v_id is not null and app.is_blocked_between(auth.uid(), v_id) then
    return null;
  end if;

  return v_id;
end;
$$;

create or replace function public.block_person(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'you cannot block yourself' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'no such account' using errcode = 'no_data_found';
  end if;

  insert into app.blocks (blocker_id, blocked_id)
  values (auth.uid(), p_user_id)
  on conflict do nothing;
end;
$$;

create or replace function public.unblock_person(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  delete from app.blocks
  where blocker_id = auth.uid() and blocked_id = p_user_id;
end;
$$;

/** Who you have blocked. Never who has blocked you. */
create or replace function public.my_blocks()
returns table (user_id uuid, full_name text, blocked_at timestamptz)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select b.blocked_id, p.full_name, b.created_at
  from app.blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------

create table app.content_reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references public.profiles (id) on delete cascade,

  subject_kind  text not null check (subject_kind in ('contract', 'dispute', 'person')),
  subject_id    uuid not null,

  reason        text not null
                  check (reason in ('abusive', 'fraud', 'impersonation', 'illegal', 'spam', 'other')),
  detail        text check (length(btrim(detail)) between 1 and 2000),

  created_at    timestamptz not null default now(),

  state         text not null default 'open'
                  check (state in ('open', 'actioned', 'dismissed')),
  reviewed_by   uuid references public.profiles (id) on delete set null,
  reviewed_at   timestamptz,
  reviewer_note text check (length(btrim(reviewer_note)) between 1 and 2000),

  constraint report_review_is_complete check (
    (state = 'open' and reviewed_by is null and reviewed_at is null)
    or (state <> 'open' and reviewed_by is not null and reviewed_at is not null)
  )
);

comment on table app.content_reports is
  'Reports raised by a party about a contract, a dispute or a person. The reported facts cannot be edited; only the review can move.';

-- One open report per person per subject. Somebody unhappy will press the
-- button more than once, and a queue with the same complaint eleven times in
-- it is a queue nobody reads.
create unique index content_reports_one_open_idx
  on app.content_reports (reporter_id, subject_kind, subject_id)
  where state = 'open';

create index content_reports_open_idx on app.content_reports (created_at desc) where state = 'open';

alter table app.content_reports enable row level security;

/**
 * What was reported cannot be rewritten; what an operator decided can.
 *
 * Not the blanket append-only trigger used on evidence and the access log: a
 * report has to be reviewable, so the state, the reviewer and the note have to
 * move. Everything a person said when they raised it is frozen, including
 * against the service role.
 */
create or replace function app.report_facts_are_fixed()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'a report cannot be deleted; dismiss it instead'
      using errcode = 'check_violation';
  end if;

  if new.reporter_id  is distinct from old.reporter_id
     or new.subject_kind is distinct from old.subject_kind
     or new.subject_id   is distinct from old.subject_id
     or new.reason       is distinct from old.reason
     or new.detail       is distinct from old.detail
     or new.created_at   is distinct from old.created_at
  then
    raise exception 'what was reported cannot be edited, only reviewed'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger content_reports_facts_fixed
  before update or delete on app.content_reports
  for each row execute function app.report_facts_are_fixed();

/**
 * Raise a report about something you are actually party to.
 *
 * The membership check is what keeps this from being a way to probe whether an
 * id exists: a stranger gets the same 'not_found' whether the subject is real
 * or not.
 */
create or replace function public.report_content(
  p_kind      text,
  p_subject_id uuid,
  p_reason    text,
  p_detail    text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_id      uuid;
  v_allowed boolean;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  v_allowed := case p_kind
    when 'contract' then app.is_transaction_party(p_subject_id)
    when 'dispute'  then app.is_dispute_party(p_subject_id)
    when 'person'   then p_subject_id <> auth.uid() and app.shares_transaction_with(p_subject_id)
    else false
  end;

  if not coalesce(v_allowed, false) then
    raise exception 'not found' using errcode = 'no_data_found';
  end if;

  -- Pressed a second time, the first report stands and its id comes back. An
  -- upsert that overwrote the detail was the first version of this, and it
  -- contradicted the freeze twenty lines below: what somebody wrote when they
  -- raised a report is the thing that must not be editable afterwards, by them
  -- least of all.
  insert into app.content_reports (reporter_id, subject_kind, subject_id, reason, detail)
  values (auth.uid(), p_kind, p_subject_id, p_reason, nullif(btrim(p_detail), ''))
  on conflict do nothing
  returning id into v_id;

  if v_id is null then
    select r.id into v_id
    from app.content_reports r
    where r.reporter_id = auth.uid()
      and r.subject_kind = p_kind
      and r.subject_id = p_subject_id
      and r.state = 'open';
  end if;

  return v_id;
end;
$$;

/** What you have reported, and what came of it. */
create or replace function public.my_reports()
returns table (
  id uuid, subject_kind text, subject_id uuid, reason text,
  created_at timestamptz, state text
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select r.id, r.subject_kind, r.subject_id, r.reason, r.created_at, r.state
  from app.content_reports r
  where r.reporter_id = auth.uid()
  order by r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- The operator side
-- ---------------------------------------------------------------------------

create or replace function public.admin_reports(p_state text default 'open')
returns table (
  id uuid, subject_kind text, subject_id uuid, reason text, detail text,
  reporter text, created_at timestamptz, state text, reviewer_note text
)
language plpgsql
stable
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_admin('reports');
  return query
    select r.id, r.subject_kind, r.subject_id, r.reason, r.detail,
           p.email, r.created_at, r.state, r.reviewer_note
    from app.content_reports r
    join public.profiles p on p.id = r.reporter_id
    where r.state = coalesce(nullif(btrim(p_state), ''), 'open')
    order by r.created_at desc
    limit 200;
end;
$$;

create or replace function public.admin_resolve_report(
  p_report_id uuid,
  p_outcome   text,
  p_note      text
)
returns void
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
begin
  perform app.assert_admin('resolve report');

  if p_outcome not in ('actioned', 'dismissed') then
    raise exception 'an outcome is actioned or dismissed' using errcode = 'check_violation';
  end if;

  -- The same ten-character floor as a suspension. A queue closed with "ok"
  -- eleven times tells the next person nothing.
  if length(btrim(coalesce(p_note, ''))) < 10 then
    raise exception 'say why, in at least ten characters' using errcode = 'check_violation';
  end if;

  update app.content_reports
  set state = p_outcome,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      reviewer_note = btrim(p_note)
  where id = p_report_id and state = 'open';

  if not found then
    raise exception 'no open report with that id' using errcode = 'no_data_found';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on all tables in schema app from anon, authenticated;

-- From `public`, not only from `anon`.
--
-- Supabase grants EXECUTE to PUBLIC on every new function in this schema, and
-- a revoke aimed at anon does not remove a right held through PUBLIC. That is
-- what migration 0024 existed to sweep up, and writing this block the obvious
-- way reintroduced it on all seven: the schema suite caught them by name.
revoke all on function public.block_person(uuid)                        from public, anon;
revoke all on function public.unblock_person(uuid)                      from public, anon;
revoke all on function public.my_blocks()                               from public, anon;
revoke all on function public.report_content(text, uuid, text, text)    from public, anon;
revoke all on function public.my_reports()                              from public, anon;
revoke all on function public.admin_reports(text)                       from public, anon;
revoke all on function public.admin_resolve_report(uuid, text, text)    from public, anon;

-- Then handed back to a signed-in caller, deliberately and one at a time. The
-- two operator functions are reachable by anybody signed in and refuse anybody
-- not on the operator list, which is where assert_admin does its work.
grant execute on function public.block_person(uuid)                     to authenticated;
grant execute on function public.unblock_person(uuid)                   to authenticated;
grant execute on function public.my_blocks()                            to authenticated;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;
grant execute on function public.my_reports()                           to authenticated;
grant execute on function public.admin_reports(text)                    to authenticated;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;

revoke all on function app.is_blocked_between(uuid, uuid)  from public, anon, authenticated;
revoke all on function app.refuse_blocked_contract()       from public, anon, authenticated;
revoke all on function app.report_facts_are_fixed()        from public, anon, authenticated;
