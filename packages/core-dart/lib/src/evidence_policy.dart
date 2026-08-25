/// What may be filed as evidence.
///
/// Ported from `packages/server/src/evidence.ts`, and kept in step with the
/// bucket's `allowed_mime_types` in `supabase/migrations/0007_evidence_storage.sql`.
/// `dart-parity.test.ts` fails if this list and the TypeScript one disagree.
///
/// The app checks these before uploading so a person is told immediately
/// rather than after a transfer that was always going to be rejected. The
/// server checks them again, because a client-side check is a courtesy and
/// never a control.
library;

/// 50 MiB, matching the DB check and the bucket's file size limit.
const int maxEvidenceBytes = 52428800;

const List<String> allowedContentTypes = [
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/webp',
  'text/plain',
  'text/markdown',
  'text/csv',
  'application/zip',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
];

/// Why an upload was refused before it left the device.
///
/// The codes match `UploadRejectionCode` in the server package for the checks
/// the app can make on its own. The server-only codes (NOT_A_PARTY,
/// DIGEST_MISMATCH, STORAGE_FAILED, RECORD_FAILED) have no Dart counterpart:
/// the app is in no position to decide them.
enum EvidenceRejection {
  emptyFile('EMPTY_FILE'),
  fileTooLarge('FILE_TOO_LARGE'),
  unsupportedContentType('UNSUPPORTED_CONTENT_TYPE'),
  invalidFilename('INVALID_FILENAME'),
  transactionClosed('TRANSACTION_CLOSED'),
  duplicateEvidence('DUPLICATE_EVIDENCE');

  const EvidenceRejection(this.wireName);
  final String wireName;
}

/// Checks what can be checked without the server: shape, not permission.
///
/// Returns null when the file is worth uploading.
EvidenceRejection? checkEvidenceShape({
  required String filename,
  required String contentType,
  required int byteSize,
}) {
  if (byteSize == 0) return EvidenceRejection.emptyFile;
  if (byteSize > maxEvidenceBytes) return EvidenceRejection.fileTooLarge;
  if (!allowedContentTypes.contains(contentType)) {
    return EvidenceRejection.unsupportedContentType;
  }
  final trimmed = filename.trim();
  if (trimmed.isEmpty || trimmed.length > 255) {
    return EvidenceRejection.invalidFilename;
  }
  // The filename is metadata shown to the other party, never a path.
  if (trimmed.contains('/') || trimmed.contains(r'\') || trimmed.contains('\u0000')) {
    return EvidenceRejection.invalidFilename;
  }
  return null;
}

/// The message a person should see. Says what to do, not what failed.
String evidenceRejectionMessage(EvidenceRejection rejection) {
  return switch (rejection) {
    EvidenceRejection.emptyFile => 'That file is empty.',
    EvidenceRejection.fileTooLarge =>
      'That file is over the 50 MB limit. Send the relevant pages rather than '
          'the whole archive.',
    EvidenceRejection.unsupportedContentType =>
      'That kind of file cannot be filed as evidence. PDFs, images, documents, '
          'plain text and zip archives are accepted.',
    EvidenceRejection.invalidFilename => 'That filename cannot be used.',
    EvidenceRejection.transactionClosed =>
      'This contract has closed and no longer accepts evidence.',
    EvidenceRejection.duplicateEvidence =>
      'This exact file has already been filed on this contract.',
  };
}
