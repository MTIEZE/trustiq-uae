import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/evidence_service.dart';
import 'package:trustiq_app/screens/add_evidence_screen.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// The evidence path exists to make one claim true: the fingerprint on the
/// record was computed from the stored bytes, not supplied by whoever uploaded
/// them. These tests pin that, and the shape rules around it.

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('the digest belongs to the receiver, not the sender', () {
    test('records the digest of the bytes that were actually stored', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final contract =
          state.contracts.firstWhere((c) => c.state == TransactionState.delivered);
      final bytes = bytesOf('the signed brief, as a pdf would be');

      final result = await state.fileEvidence(
        contractId: contract.id,
        filename: 'brief.pdf',
        contentType: 'application/pdf',
        bytes: bytes,
      );

      expect(result, isA<EvidenceUploaded>());
      final item = (result as EvidenceUploaded).item;
      expect(item.sha256, sha256Hex(bytes));
      expect(item.sha256, hasLength(64));
    });

    test('a single changed byte produces a different fingerprint', () async {
      // The property the whole evidence vault rests on: tampering is visible.
      final original = sha256Hex(bytesOf('the signed brief'));
      // One character changed, nothing else.
      final tampered = sha256Hex(bytesOf('the signed briefs'));
      expect(tampered, isNot(original));

      // And the same bytes always give the same digest, or nothing could be
      // checked against anything.
      expect(sha256Hex(bytesOf('the signed brief')), original);
    });

    test('the filed item lands on the contract and is visible to both sides', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final contract =
          state.contracts.firstWhere((c) => c.state == TransactionState.delivered);
      final before = contract.evidence.length;

      await state.fileEvidence(
        contractId: contract.id,
        filename: 'invoice.pdf',
        contentType: 'application/pdf',
        bytes: bytesOf('invoice contents'),
      );

      final after = state.contractById(contract.id).evidence;
      expect(after.length, before + 1);
      // Filed under the role that uploaded it, taken from the session rather
      // than from anything the caller asserted.
      expect(after.last.uploadedByRole, state.viewingAs);
    });

    test('the uploader role comes from who you are, not from the call', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final contract =
          state.contracts.firstWhere((c) => c.state == TransactionState.delivered);

      state.viewAs(Role.seller);
      await state.fileEvidence(
        contractId: contract.id,
        filename: 'delivery.zip',
        contentType: 'application/zip',
        bytes: bytesOf('zip contents'),
      );

      expect(state.contractById(contract.id).evidence.last.uploadedByRole, Role.seller);
    });
  });

  group('what may be filed', () {
    late AppState state;
    late String contractId;

    setUp(() async {
      state = AppState(backend: DemoBackend());
      await state.refresh();
      contractId = state.contracts
          .firstWhere((c) => c.state == TransactionState.delivered)
          .id;
    });

    Future<EvidenceUploadResult> file({
      String name = 'doc.pdf',
      String type = 'application/pdf',
      Uint8List? bytes,
    }) =>
        state.fileEvidence(
          contractId: contractId,
          filename: name,
          contentType: type,
          bytes: bytes ?? bytesOf('some content'),
        );

    test('refuses an empty file', () async {
      final result = await file(bytes: Uint8List(0));
      expect((result as EvidenceRefused).reason, EvidenceRejection.emptyFile);
    });

    test('refuses a type the bucket will not hold', () async {
      final result = await file(name: 'tool.exe', type: 'application/x-msdownload');
      expect((result as EvidenceRefused).reason, EvidenceRejection.unsupportedContentType);
    });

    test('refuses a filename carrying path separators', () async {
      for (final name in ['../../etc/passwd', 'a/b.pdf', r'a\b.pdf']) {
        final result = await file(name: name);
        expect((result as EvidenceRefused).reason, EvidenceRejection.invalidFilename,
            reason: name);
      }
    });

    test('accepts an ordinary filename with a space in it', () async {
      // Rejecting spaces would turn away most real documents.
      final result = await file(name: 'signed brief.pdf');
      expect(result, isA<EvidenceUploaded>());
    });

    test('refuses the same bytes twice on one contract', () async {
      await file(name: 'first.pdf', bytes: bytesOf('identical'));
      final second = await file(name: 'renamed.pdf', bytes: bytesOf('identical'));
      expect((second as EvidenceRefused).reason, EvidenceRejection.duplicateEvidence);
    });

    test('refuses evidence against a closed contract', () async {
      final completed = state.contracts
          .firstWhere((c) => c.state == TransactionState.completed);
      final result = await state.fileEvidence(
        contractId: completed.id,
        filename: 'late.pdf',
        contentType: 'application/pdf',
        bytes: bytesOf('too late'),
      );
      expect((result as EvidenceRefused).reason, EvidenceRejection.transactionClosed);
      expect(state.contractById(completed.id).evidence, isEmpty);
    });

    test('a refusal writes nothing', () async {
      final before = state.contractById(contractId).evidence.length;
      await file(name: 'tool.exe', type: 'application/x-msdownload');
      expect(state.contractById(contractId).evidence.length, before);
    });
  });

  group('shape rules match the server', () {
    test('the size ceiling is the one the bucket enforces', () async {
      expect(maxEvidenceBytes, 52428800);
      expect(
        checkEvidenceShape(
          filename: 'big.zip',
          contentType: 'application/zip',
          byteSize: maxEvidenceBytes + 1,
        ),
        EvidenceRejection.fileTooLarge,
      );
      expect(
        checkEvidenceShape(
          filename: 'big.zip',
          contentType: 'application/zip',
          byteSize: maxEvidenceBytes,
        ),
        isNull,
      );
    });

    test('a real null character in a filename is refused', () async {
      final withNul = 'a${String.fromCharCode(0)}b.pdf';
      expect(
        checkEvidenceShape(
          filename: withNul,
          contentType: 'application/pdf',
          byteSize: 10,
        ),
        EvidenceRejection.invalidFilename,
      );
    });

    test('every allowed content type is actually accepted', () async {
      for (final type in allowedContentTypes) {
        expect(
          checkEvidenceShape(filename: 'f.bin', contentType: type, byteSize: 1),
          isNull,
          reason: type,
        );
      }
    });
  });

  group('what the person reads', () {
    test('file sizes are rendered in units a person uses', () async {
      expect(humanSize(512), '512 bytes');
      expect(humanSize(2048), '2 KB');
      expect(humanSize(5 * 1024 * 1024), '5.0 MB');
    });

    test('every rejection has a message that says what to do', () async {
      for (final rejection in EvidenceRejection.values) {
        final message = evidenceRejectionMessage(rejection);
        expect(message.trim(), isNotEmpty, reason: rejection.name);
        // Never leak the wire code to a person.
        expect(message, isNot(contains(rejection.wireName)), reason: rejection.name);
      }
    });
  });
}
