-- ---------------------------------------------------------------------------
-- 0010  What the document actually says
--
-- Until now the model was handed a filename, a content type and whatever note
-- the uploader typed. It grounded findings in documents it had never read.
--
-- Two columns, and the second matters as much as the first.
--
-- `extracted_text` is the readable content, captured once at upload from the
-- same bytes the digest was computed over. Like the rest of this table it is
-- written once and never changed.
--
-- `extraction_status` says which kind of nothing an absent text is. "No text
-- because this is a photograph" and "no text because we could not read this
-- file" are different facts about a case: the second means there is content
-- the model is not seeing, which is a reason for it to be less confident. A
-- single nullable text column would collapse the two and quietly flatter the
-- evidence.
--
--   not_attempted  filed before extraction existed. Not a judgement about the
--                  file, and deliberately distinct from the others: it must
--                  not read as "we looked and found nothing".
--   unsupported    the type is not one we read. Images and PDFs land here
--                  until there is OCR and a PDF parser.
--   failed         we should have been able to read it and could not.
--   extracted      the whole document is in extracted_text.
--   truncated      the start of the document is in extracted_text.
--
-- Truncation is recorded here rather than marked inside the text, because the
-- text is written by a party to the dispute and anyone can type "[truncated]".
-- Everything the prompt says *about* party content is rendered outside the
-- quoted block, and this is the same rule.
-- ---------------------------------------------------------------------------

alter table public.evidence
  add column extracted_text text,
  add column extraction_status text not null default 'not_attempted';

-- The ceiling matches MAX_EXTRACTED_CHARS in packages/server/src/text-extraction.ts.
-- A test in that package parses this file and fails if the two drift apart.
alter table public.evidence
  add constraint evidence_extracted_text_length
    check (extracted_text is null or length(extracted_text) <= 20000);

alter table public.evidence
  add constraint evidence_extraction_status_known
    check (extraction_status in ('not_attempted', 'unsupported', 'failed', 'extracted', 'truncated'));

-- Text exists exactly when the status says it does. Without this, a row could
-- claim 'extracted' with nothing in it, or carry text under 'failed' that no
-- reader would think to look at.
alter table public.evidence
  add constraint evidence_extraction_status_matches_text
    check (
      (extraction_status in ('extracted', 'truncated') and extracted_text is not null
        and length(btrim(extracted_text)) > 0)
      or (extraction_status in ('not_attempted', 'unsupported', 'failed') and extracted_text is null)
    );

comment on column public.evidence.extracted_text is
  'Readable content of the document, captured server-side at upload from the bytes the digest covers. Never supplied by the client. Append-only with the rest of the row.';
comment on column public.evidence.extraction_status is
  'Why extracted_text is present or absent. not_attempted marks rows filed before extraction existed; unsupported means the file type is not read; failed means it should have been readable and was not.';

-- Rows that already exist keep 'not_attempted'. There is no backfill: the
-- bytes would have to be re-read out of storage, which is a batch job and not
-- a migration, and a wrong status is worse than an honest one.
