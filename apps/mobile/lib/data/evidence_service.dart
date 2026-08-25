import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'demo_data.dart';

/// Uploading evidence.
///
/// The rule this whole path exists to protect: **the digest that gets recorded
/// is computed from the stored bytes by the server, never supplied by the
/// device**. Migration 0007 removed the client's ability to write evidence
/// rows at all, precisely so this cannot be worked around.
///
/// The app still hashes the file locally, but only to send alongside the bytes
/// as a claim the server checks against its own. That catches a transfer that
/// arrived corrupted. It is not a security measure and is not treated as one:
/// a client that wanted to lie would simply omit it.
abstract interface class EvidenceUploader {
  Future<EvidenceUploadResult> upload({
    required String contractId,
    required Role uploaderRole,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  });
}

sealed class EvidenceUploadResult {
  const EvidenceUploadResult();
}

final class EvidenceUploaded extends EvidenceUploadResult {
  const EvidenceUploaded(this.item);

  /// Carries the digest the server computed, which is the one shown and the
  /// one stored. The locally computed value is discarded once checked.
  final EvidenceItem item;
}

final class EvidenceRefused extends EvidenceUploadResult {
  const EvidenceRefused(this.reason, this.message);
  final EvidenceRejection reason;
  final String message;
}

/// The digest of some bytes, lowercase hex.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// Stands in for the server until the Supabase adapters exist.
///
/// It deliberately mirrors `uploadEvidence` in `packages/server`: the same
/// shape checks, the same duplicate rule, and the digest computed on the
/// receiving side rather than trusted from the caller. When the real backend
/// lands, this class is replaced and nothing above it changes.
class InMemoryEvidenceUploader implements EvidenceUploader {
  InMemoryEvidenceUploader(this._contracts);

  /// Reads current contract state so the closed-contract and duplicate rules
  /// can be applied the way the server applies them.
  final List<Contract> Function() _contracts;

  int _counter = 0;

  @override
  Future<EvidenceUploadResult> upload({
    required String contractId,
    required Role uploaderRole,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  }) async {
    // What the device could already tell, checked again here because the
    // client-side check is a courtesy and never a control.
    final shape = checkEvidenceShape(
      filename: filename,
      contentType: contentType,
      byteSize: bytes.length,
    );
    if (shape != null) {
      return EvidenceRefused(shape, evidenceRejectionMessage(shape));
    }

    final contract = _contracts().firstWhere((c) => c.id == contractId);

    const accepting = {
      TransactionState.draft,
      TransactionState.pendingAcceptance,
      TransactionState.active,
      TransactionState.delivered,
      TransactionState.disputed,
    };
    if (!accepting.contains(contract.state)) {
      return EvidenceRefused(
        EvidenceRejection.transactionClosed,
        evidenceRejectionMessage(EvidenceRejection.transactionClosed),
      );
    }

    // The digest, computed here, from these bytes.
    final digest = sha256Hex(bytes);

    if (contract.evidence.any((e) => e.sha256 == digest)) {
      return EvidenceRefused(
        EvidenceRejection.duplicateEvidence,
        evidenceRejectionMessage(EvidenceRejection.duplicateEvidence),
      );
    }

    _counter += 1;
    return EvidenceUploaded(
      EvidenceItem(
        id: 'ev_${DateTime.now().microsecondsSinceEpoch}_$_counter',
        filename: filename,
        uploadedByRole: uploaderRole,
        uploadedAt: DateTime.now(),
        sha256: digest,
        note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      ),
    );
  }
}
