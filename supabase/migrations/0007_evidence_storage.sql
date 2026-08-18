-- ---------------------------------------------------------------------------
-- 0007  Evidence storage, and closing the SHA-256 hole
--
-- 0004 documented public.evidence.sha256 as "computed server-side at upload",
-- but nothing enforced it: the insert policy let a party write the row, which
-- means a party could also choose the digest. A hash the uploader picks proves
-- nothing, and the evidence vault is the foundation the dispute rests on.
--
-- The fix has two halves and needs both:
--   1. Clients can no longer insert into public.evidence at all. Rows are
--      created only by the upload path, which hashes the bytes it stored.
--   2. Clients can no longer write to the storage bucket either. Otherwise a
--      party could replace the object after the row was written and the
--      recorded digest would describe a file that no longer exists.
-- ---------------------------------------------------------------------------

-- Private bucket. No public URLs: reads go through a signed URL issued after
-- the RLS check below passes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evidence',
  'evidence',
  false,
  52428800,
  array[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/webp',
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/zip',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Storage access
--
-- Read is allowed to the parties of the contract the object belongs to. The
-- join goes through public.evidence rather than parsing the object path, so a
-- crafted path cannot grant access to an object that has no evidence row.
--
-- There is deliberately no insert, update or delete policy: only the service
-- role writes to this bucket.
-- ---------------------------------------------------------------------------

drop policy if exists evidence_objects_read on storage.objects;

create policy evidence_objects_read
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'evidence'
    and exists (
      select 1
      from public.evidence e
      where e.storage_path = storage.objects.name
        and app.is_transaction_party(e.transaction_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Evidence rows become server-written
-- ---------------------------------------------------------------------------

drop policy if exists evidence_insert_party on public.evidence;

comment on column public.evidence.sha256 is
  'Lowercase hex SHA-256 of the stored object, computed by the upload path from the bytes it wrote. Clients cannot insert evidence rows (no INSERT policy), so this value is never client-supplied.';

comment on table public.evidence is
  'Append-only evidence attached to a transaction. Written only by the server-side upload path; readable by the parties. Deleting or altering a row is blocked by trigger, even for roles that bypass RLS.';

-- app.transaction_accepts_evidence is still used by the upload path to decide
-- whether a contract is in a state that can receive evidence. It stays.
