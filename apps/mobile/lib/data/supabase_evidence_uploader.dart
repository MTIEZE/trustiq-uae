import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'config.dart';
import 'demo_data.dart';
import 'evidence_service.dart';

/// Files a document through the `file-evidence` Edge Function.
///
/// The bytes go to the server and the server hashes them. That is the whole
/// arrangement, and it is why this is a multipart POST rather than a direct
/// upload to storage: an upload the server never sees is an upload whose
/// digest the server cannot compute, and the digest is what lets either party
/// prove months later that a document was not swapped.
///
/// The app hashes the file too, and sends that alongside. It is a claim, not a
/// control: the server checks it against its own and refuses the upload if
/// they differ. That catches a transfer corrupted in flight. It catches
/// nothing else, because a client that wanted to lie would simply leave the
/// field out, and the server would still compute the digest itself.
class SupabaseEvidenceUploader implements EvidenceUploader {
  SupabaseEvidenceUploader(this._client, this._config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final TrustIqConfig _config;
  final http.Client _http;

  Uri get _endpoint => Uri.parse('${_config.url}/functions/v1/file-evidence');

  @override
  Future<EvidenceUploadResult> upload({
    required String contractId,
    required Role uploaderRole,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  }) async {
    // Checked here so a person is told immediately rather than after a
    // transfer that was always going to be rejected. The server checks the
    // same things again, because a client-side check is a courtesy and never
    // a control.
    final shape = checkEvidenceShape(
      filename: filename,
      contentType: contentType,
      byteSize: bytes.length,
    );
    if (shape != null) {
      return EvidenceRefused(shape, evidenceRejectionMessage(shape));
    }

    final token = _client.auth.currentSession?.accessToken;
    if (token == null) {
      return const EvidenceRefused(
        EvidenceRejection.transactionClosed,
        'Your session has expired. Sign in again and try once more.',
      );
    }

    final request = http.MultipartRequest('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['apikey'] = _config.anonKey
      ..fields['transactionId'] = contractId
      ..fields['contentType'] = contentType
      ..fields['sha256'] = sha256Hex(bytes);
    if (note != null && note.trim().isNotEmpty) {
      request.fields['note'] = note.trim();
    }
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      return EvidenceRefused(
        EvidenceRejection.transactionClosed,
        'The document could not be sent: $e',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return EvidenceRefused(
        EvidenceRejection.transactionClosed,
        'The server answered with something this app could not read '
        '(HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode != 201) {
      return EvidenceRefused(
        _rejectionFor(body['code'] as String?),
        (body['error'] as String?) ?? 'The document was refused.',
      );
    }

    return EvidenceUploaded(
      EvidenceItem(
        id: body['evidenceId'] as String,
        filename: filename,
        uploadedByRole: uploaderRole,
        uploadedAt: DateTime.now(),
        // The server's digest, not the one computed above. The local value was
        // only ever a claim and is discarded the moment it has been checked.
        sha256: body['sha256'] as String,
        note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      ),
    );
  }

  /// Maps the server's rejection code onto the one the app knows.
  ///
  /// Four of the server's codes have no counterpart here on purpose:
  /// NOT_A_PARTY, DIGEST_MISMATCH, STORAGE_FAILED and RECORD_FAILED are things
  /// the device is in no position to decide. They arrive with the server's own
  /// message, which is shown as written.
  static EvidenceRejection _rejectionFor(String? code) => switch (code) {
        'EMPTY_FILE' => EvidenceRejection.emptyFile,
        'FILE_TOO_LARGE' => EvidenceRejection.fileTooLarge,
        'UNSUPPORTED_CONTENT_TYPE' => EvidenceRejection.unsupportedContentType,
        'INVALID_FILENAME' => EvidenceRejection.invalidFilename,
        'DUPLICATE_EVIDENCE' => EvidenceRejection.duplicateEvidence,
        _ => EvidenceRejection.transactionClosed,
      };
}
