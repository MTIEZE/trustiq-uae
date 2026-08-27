-- ---------------------------------------------------------------------------
-- Local test stubs.
--
-- NOT a migration. Supabase provides all of this; a bare Postgres container
-- does not. Applying it first lets the real migrations run unmodified against
-- plain Postgres, so the SQL we test is the SQL we ship.
-- ---------------------------------------------------------------------------

create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text
);

-- Mirrors Supabase's auth.uid(), reading the request-scoped JWT claim.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid;
$$;

-- Supabase Storage. Only the columns the migrations actually touch.
create schema if not exists storage;

create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null unique,
  public             boolean not null default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz not null default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text not null references storage.buckets (id),
  name       text not null,
  owner      uuid,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);

alter table storage.objects enable row level security;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

grant usage on schema public  to anon, authenticated, service_role;
grant usage on schema auth    to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;
grant select on storage.objects to authenticated;

-- PostgREST grants table privileges to these roles; RLS then narrows the rows.
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated;

-- The one that cost us. A real Supabase project hands EXECUTE on every new
-- function in `public` to anon, authenticated and service_role automatically.
-- This harness did not, so `revoke all ... from public` in a migration looked
-- like it removed a grant nobody had, and four assertions saying a system
-- function was out of reach passed while the deployed project let anyone with
-- the publishable key call it. A test bed that is safer than production tests
-- nothing worth knowing.
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
