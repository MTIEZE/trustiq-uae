-- ---------------------------------------------------------------------------
-- 0017  Draining the outbox
--
-- 0016 wrote notifications and deliberately sent nothing. This is the half
-- that sends, and it is still not a trigger: the database has no pg_net and no
-- pg_cron, and it should not have them for this. Something outside asks what
-- is waiting, sends it, and says what happened.
--
-- Three things shape what the sender is given.
--
-- **One email per person, not per event.** Three moves in an afternoon is one
-- message about three things. A mail per transition is how a useful product
-- becomes a filter rule.
--
-- **A grace period.** Rows are only offered once they have sat for a few
-- minutes, so a person making two moves in a row does not generate two
-- emails a minute apart. Nothing here is real time and pretending otherwise
-- would only cost the recipient attention.
--
-- **The sender is told nothing it has to translate.** It gets a count and the
-- contract descriptions, which the parties wrote themselves. The vocabulary
-- for transitions lives in the app, in two languages, behind tests; a second
-- copy in the sender would drift from it the first time either changed, and
-- the drift would show up as an Arabic reader getting an English email.
-- ---------------------------------------------------------------------------

-- Which language to write to somebody in.
--
-- Until now the choice lived only on the device, which is right for reading
-- the sign-in screen before there is an account and useless for writing to
-- somebody who is not holding the phone.
alter table public.profiles
  add column preferred_locale text
    check (preferred_locale is null or preferred_locale in ('en', 'ar'));

comment on column public.profiles.preferred_locale is
  'Set by the app when somebody chooses a language, so mail can be written in it. Null means nobody has chosen and the device was following its own setting.';

create or replace function public.set_preferred_locale(p_locale text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  update public.profiles
  set preferred_locale = p_locale
  where id = auth.uid();
end;
$$;

comment on function public.set_preferred_locale is
  'The one identity column a person may write about themselves. Which language to be written to in is a preference, not a claim about who they are.';

-- ---------------------------------------------------------------------------
-- What is waiting, per person
-- ---------------------------------------------------------------------------

create or replace function public.notifications_to_send(
  p_grace interval default '5 minutes'
)
returns table (
  recipient_id uuid,
  email        text,
  full_name    text,
  locale       text,
  waiting      integer,
  contracts    text[],
  ids          bigint[]
)
language sql
stable
security definer
set search_path = public, app, pg_temp
as $$
  select
    n.recipient_id,
    p.email,
    p.full_name,
    coalesce(p.preferred_locale, 'en'),
    count(*)::integer,
    -- Distinct, because three moves on one contract is one line in the mail,
    -- and ordered so two runs of the same batch read the same way.
    array_agg(distinct t.description order by t.description),
    array_agg(n.id order by n.id)
  from app.notifications n
  join public.profiles p on p.id = n.recipient_id
  join public.transactions t on t.id = n.transaction_id
  where n.needs_you
    and n.emailed_at is null
    and n.email_error is null
    and n.read_at is null            -- they already saw it in the app
    and n.created_at <= now() - p_grace
  group by n.recipient_id, p.email, p.full_name, p.preferred_locale;
$$;

comment on function public.notifications_to_send is
  'One row per person with something waiting, not one per event. Skips anything already read in the app: a mail about something somebody has dealt with is worse than no mail.';

create or replace function public.mark_notifications_sent(
  p_ids   bigint[],
  p_error text default null
)
returns integer
language plpgsql
security definer
set search_path = public, app, pg_temp
as $$
declare
  v_rows integer;
begin
  -- Both outcomes are recorded. A failure that left the rows untouched would
  -- be retried forever against whatever is refusing them, and nobody would
  -- know it was happening.
  update app.notifications
  set emailed_at  = case when p_error is null then now() else null end,
      email_error = p_error
  where id = any (p_ids);

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- These two live in `public` rather than in `app`, unlike the table they read.
-- PostgREST only exposes `public`, and the sender is an edge function talking
-- through the Supabase client like everything else. They are the sender's
-- alone: no client has any business reading who is about to be written to, so
-- the grant goes to service_role and nowhere else, and the sweep in
-- schema.test.sql checks that the automatic grants were taken back.
-- ---------------------------------------------------------------------------

revoke all on function public.notifications_to_send(interval) from public, anon, authenticated;
revoke all on function public.mark_notifications_sent(bigint[], text) from public, anon, authenticated;
grant execute on function public.notifications_to_send(interval) to service_role;
grant execute on function public.mark_notifications_sent(bigint[], text) to service_role;

revoke all on function public.set_preferred_locale(text) from public, anon;
grant execute on function public.set_preferred_locale(text) to authenticated;
