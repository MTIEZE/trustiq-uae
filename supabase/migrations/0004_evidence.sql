-- ---------------------------------------------------------------------------
-- 0004  Evidence
--
-- The evidence vault is what makes a dispute resolvable. Two properties matter
-- more than anything else here:
--
--   1. Rows are append-only. A party cannot quietly swap or delete a document
--      after the other side has seen it.
--   2. Every row carries the SHA-256 of the stored file, recorded at upload.
--      That is what lets either party prove months later that the file backing
--      a finding is the file that was submitted.
-- ---------------------------------------------------------------------------

create table public.evidence (
  id               uuid primary key default gen_random_uuid(),
  transaction_id   uuid not null references public.transactions (id) on delete cascade,

  uploaded_by      uuid not null references public.profiles (id) on delete restrict,
  uploaded_by_role public.party_role not null,

  -- Object key inside the private `evidence` storage bucket.
  storage_path     text not null unique check (length(btrim(storage_path)) > 0),
  filename         text not null check (length(btrim(filename)) between 1 and 255),
  content_type     text not null check (length(btrim(content_type)) between 1 and 255),
  byte_size        bigint not null check (byte_size > 0 and byte_size <= 52428800),

  sha256           char(64) not null check (sha256 ~ '^[0-9a-f]{64}$'),

  note             text check (length(note) <= 2000),
  uploaded_at      timestamptz not null default now()
);

comment on table public.evidence is
  'Append-only evidence attached to a transaction. sha256 is recorded at upload so tampering is detectable.';
comment on column public.evidence.sha256 is
  'Lowercase hex SHA-256 of the stored object, computed server-side at upload. Never supplied by the client.';

create index evidence_transaction_idx on public.evidence (transaction_id, uploaded_at);
create index evidence_uploader_idx    on public.evidence (uploaded_by);

-- Same digest twice in one contract is the same document. Storing it once keeps
-- the AI from being handed duplicates and weighing the same fact twice.
create unique index evidence_unique_digest_per_transaction
  on public.evidence (transaction_id, sha256);

create trigger evidence_immutable
  before update or delete on public.evidence
  for each row execute function app.forbid_mutation();

-- The declared role must match the uploader's actual side of the contract.
create or replace function app.check_evidence_role()
returns trigger
language plpgsql
as $$
declare
  v_buyer  uuid;
  v_seller uuid;
begin
  select t.buyer_id, t.seller_id into v_buyer, v_seller
  from public.transactions t
  where t.id = new.transaction_id;

  if new.uploaded_by = v_buyer and new.uploaded_by_role <> 'buyer' then
    raise exception 'uploader is the buyer on this contract but declared %', new.uploaded_by_role
      using errcode = 'check_violation';
  elsif new.uploaded_by = v_seller and new.uploaded_by_role <> 'seller' then
    raise exception 'uploader is the seller on this contract but declared %', new.uploaded_by_role
      using errcode = 'check_violation';
  elsif new.uploaded_by not in (v_buyer, v_seller) then
    raise exception 'uploader is not a party to transaction %', new.transaction_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger evidence_role_matches_contract
  before insert on public.evidence
  for each row execute function app.check_evidence_role();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

-- Evidence is accepted while a contract is live or contested, and refused once
-- it has reached a terminal state.
create or replace function app.transaction_accepts_evidence(p_transaction_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.transactions t
    where t.id = p_transaction_id
      and t.state in ('draft', 'pending_acceptance', 'active', 'delivered', 'disputed')
  );
$$;

alter table public.evidence enable row level security;

create policy evidence_select_party
  on public.evidence for select
  to authenticated
  using (app.is_transaction_party(transaction_id));

-- Evidence can be added while the contract is live or contested, never once it
-- has closed. Filing a document against a settled case has no meaning.
create policy evidence_insert_party
  on public.evidence for insert
  to authenticated
  with check (
    uploaded_by = auth.uid()
    and app.is_transaction_party(transaction_id)
    and app.transaction_accepts_evidence(transaction_id)
  );

-- No update or delete policy, and the trigger above blocks both even for roles
-- that bypass RLS.
