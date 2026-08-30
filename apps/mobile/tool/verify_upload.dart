// Files a document through the app's own uploader, against the live project.
//
//   flutter test tool/verify_upload.dart
//
// scripts/test-file-evidence.mjs already proves the endpoint, with twenty-nine
// checks driven by hand-written HTTP. What it cannot prove is that the code
// inside the app reaches that endpoint correctly: the multipart it builds, the
// token it attaches, the role it derives, the answer it parses. Every piece of
// evidence in the live database was put there by a script, so the path a real
// person's phone would take had never once been walked.
//
// This walks it. Same class the app builds, same call the screen makes, same
// project. Nothing here is a mock.
//
// A test file because that is how you run Dart with the app's dependencies
// resolved. It asserts, but it is not part of the suite: it spends network and
// creates rows that stay, so `flutter test` on its own does not run it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:trustiq_app/data/config.dart';
import 'package:trustiq_app/data/evidence_service.dart';
import 'package:trustiq_app/data/supabase_evidence_uploader.dart';
import 'package:trustiq_core/trustiq_core.dart';

Map<String, String> readEnv() {
  final file = File('../../.env');
  if (!file.existsSync()) {
    throw StateError('No .env at ${file.absolute.path}');
  }
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final at = trimmed.indexOf('=');
    if (at != -1) out[trimmed.substring(0, at).trim()] = trimmed.substring(at + 1).trim();
  }
  return out;
}

void main() {
  test('the app files a document and the server hashes it', () async {
    final env = readEnv();
    for (final key in ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
      expect(env[key], isNotNull, reason: '$key is not set in .env');
    }

    final url = env['SUPABASE_URL']!;
    final run = 'app-upload-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final password = 'Trustiq!${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final buyerEmail = 'app.buyer.$run@example.test';
    final sellerEmail = 'app.seller.$run@example.test';

    // The service role sets the scene. It is never used for the upload itself:
    // that is the whole point, and the app has no access to this key.
    final admin = SupabaseClient(url, env['SUPABASE_SERVICE_ROLE_KEY']!);

    Future<String> makeAccount(String email, String name) async {
      final user = await admin.auth.admin.createUser(
        AdminUserAttributes(email: email, password: password, emailConfirm: true),
      );
      final id = user.user!.id;
      await admin.from('profiles').insert({'id': id, 'full_name': name, 'email': email});
      await admin.rpc('record_manual_verification', params: {
        'p_user_id': id,
        'p_note': 'Verified for the app upload check ($run)',
      });
      return id;
    }

    final buyerId = await makeAccount(buyerEmail, 'Uploading Client');
    final sellerId = await makeAccount(sellerEmail, 'Receiving Freelancer');

    // From here on, only what the app itself holds: the publishable key and a
    // session belonging to a person.
    final app = SupabaseClient(url, env['SUPABASE_ANON_KEY']!);
    await app.auth.signInWithPassword(email: buyerEmail, password: password);
    expect(app.auth.currentSession, isNotNull, reason: 'the app could not sign in');

    final contract = await app.from('transactions').insert({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'description': 'Upload check [$run]',
      'terms': 'A document is filed from the app.',
      'total_amount_fils': 50000,
      'created_by': buyerId,
    }).select('id').single();
    final contractId = contract['id'] as String;

    await app.rpc('apply_transaction_event',
        params: {'p_transaction_id': contractId, 'p_event': 'submit'});

    // The same object main.dart builds for a live project.
    final config = TrustIqConfig.of(url: url, anonKey: env['SUPABASE_ANON_KEY']!);
    final uploader = SupabaseEvidenceUploader(app, config);

    final bytes = Uint8List.fromList(
      utf8.encode('Filed from the app at ${DateTime.now().toIso8601String()}.\n'),
    );

    final result = await uploader.upload(
      contractId: contractId,
      // Passed, but the server derives the real role from the session. The
      // endpoint test pins that; here it only has to not be refused.
      uploaderRole: Role.buyer,
      filename: 'filed-from-the-app.txt',
      contentType: 'text/plain',
      bytes: bytes,
      note: 'Uploaded by tool/verify_upload.dart',
    );

    expect(result, isA<EvidenceUploaded>(),
        reason: 'the app could not file a document: $result');

    final filed = result as EvidenceUploaded;
    // ignore: avoid_print
    print('  filed ${filed.item.filename}');
    // ignore: avoid_print
    print('  digest ${filed.item.sha256}');

    // The digest has to be the server's, computed from the bytes it stored.
    // Anything else and the fingerprint is a claim rather than a fact.
    final row = await admin
        .from('evidence')
        .select('id, filename, sha256, byte_size, extraction_status, uploaded_by, uploaded_by_role')
        .eq('transaction_id', contractId)
        .single();

    expect(row['filename'], 'filed-from-the-app.txt');
    expect(row['byte_size'], bytes.length);
    expect(row['sha256'], filed.item.sha256,
        reason: 'the row and what the app was told must agree');
    expect(row['uploaded_by'], buyerId,
        reason: 'the uploader is taken from the session, never from the call');
    expect(row['uploaded_by_role'], 'buyer');
    expect(row['extraction_status'], 'extracted',
        reason: 'a text file should have been read');

    // ignore: avoid_print
    print('  the server stored it as ${row['id']}, ${row['byte_size']} bytes, '
        'attributed to the signed-in person');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
