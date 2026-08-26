import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/data/config.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/data/rows.dart';
import 'package:trustiq_app/screens/dispute_screen.dart' show unreadableNote;
import 'package:trustiq_core/trustiq_core.dart';

/// The two pure pieces of the live backend: the key guard, and turning rows
/// into the model. Everything else in `supabase_backend.dart` is queries, and
/// a query is proved against a database rather than against a mock of one.

void main() {
  group('the key a build is allowed to carry', () {
    String jwtWith(String role) {
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return '${seg({'alg': 'HS256'})}.${seg({'role': role, 'iss': 'supabase'})}.signature';
    }

    test('lets a publishable key through', () {
      expect(describeServiceRoleKey('sb_publishable_abc123'), isNull);
    });

    test('lets an anon JWT through', () {
      expect(describeServiceRoleKey(jwtWith('anon')), isNull);
    });

    test('catches the new secret key format', () {
      expect(describeServiceRoleKey('sb_secret_abc123'), contains('sb_secret_'));
    });

    test('catches a service_role JWT, which looks like any other JWT', () {
      // This is the one that matters. Nothing about the string says what it
      // is, so a person copying keys out of a dashboard cannot tell them
      // apart, and the app would work perfectly until somebody opened the
      // bundle and read every contract in the system.
      expect(describeServiceRoleKey(jwtWith('service_role')), contains('service_role'));
    });

    test('is not fooled by a key that merely contains the words', () {
      expect(describeServiceRoleKey('sb_publishable_service_role_lookalike'), isNull);
    });

    test('says nothing about a string that is not a key at all', () {
      expect(describeServiceRoleKey('hello'), isNull);
      expect(describeServiceRoleKey(''), isNull);
      expect(describeServiceRoleKey('a.b.c'), isNull);
    });
  });

  group('reading money off a row', () {
    test('accepts a bigint sent as a number', () {
      expect(readFils(50000, 'x').value, 50000);
    });

    test('accepts a bigint sent as a string, which PostgREST does for large values', () {
      // Just under the domain ceiling of about 92 billion AED. Anything above
      // it is refused by Fils itself, which is the behaviour we want here too.
      expect(readFils('9223372036854', 'x').value, 9223372036854);
    });

    test('lets the domain refuse an amount beyond what it supports', () {
      expect(() => readFils('9223372036855', 'x'), throwsA(anything));
    });

    test('refuses null rather than treating a missing amount as nothing', () {
      // A contract worth zero and a contract whose amount failed to load are
      // very different things, and only one of them should reach a screen.
      expect(() => readFils(null, 'total_amount_fils'), throwsA(isA<RowMappingException>()));
    });

    test('refuses a decimal, because money here is a whole number of fils', () {
      expect(() => readFils(12.5, 'x'), throwsA(isA<RowMappingException>()));
    });

    test('refuses text that is not a number', () {
      expect(() => readFils('lots', 'x'), throwsA(isA<RowMappingException>()));
    });
  });

  group('reading enums off a row', () {
    test('maps the wire names the database stores', () {
      expect(readTransactionState('pending_acceptance'), TransactionState.pendingAcceptance);
      expect(readDisputeState('ai_review'), DisputeState.aiReview);
      expect(readRole('seller', 'x'), Role.seller);
      expect(readActor('system', 'x'), Actor.system);
      expect(readDecision('refund_to_buyer'), ResolutionDecision.refundToBuyer);
    });

    test('refuses a value this build does not know', () {
      // The database moving ahead of a shipped app is a real situation. Falling
      // back to `draft` would show a resolved contract as a draft, which is
      // worse than a visible failure.
      expect(() => readTransactionState('settled_by_arbitration'),
          throwsA(isA<RowMappingException>()));
    });

    test('refuses the Dart name, so a rename cannot pass silently', () {
      expect(() => readTransactionState('pendingAcceptance'),
          throwsA(isA<RowMappingException>()));
    });
  });

  group('reading a person off a row', () {
    test('reads verification from the timestamp the server wrote', () {
      final verified = partyFromProfile(
        {'id': 'u1', 'full_name': 'Sara', 'identity_verified_at': '2026-08-01T00:00:00Z'},
        'u1',
      );
      expect(verified.verified, isTrue);
      expect(verified.name, 'Sara');
    });

    test('treats a missing timestamp as unverified, never as verified', () {
      final party = partyFromProfile(
        {'id': 'u1', 'full_name': 'Sara', 'identity_verified_at': null},
        'u1',
      );
      expect(party.verified, isFalse);
    });

    test('falls back to the email when there is no name', () {
      final party = partyFromProfile(
        {'id': 'u1', 'full_name': '  ', 'email': 'sara@design.ae'},
        'u1',
      );
      expect(party.name, 'sara@design.ae');
    });

    test('does not invent a verified person when the profile is not visible', () {
      final unknown = partyFromProfile(null, 'u9');
      expect(unknown.id, 'u9');
      expect(unknown.verified, isFalse);
    });
  });

  group('reading a document off its row', () {
    Map<String, dynamic> evidenceRow({String? status}) => {
          'id': 'ev_1',
          'filename': 'brief.pdf',
          'uploaded_by_role': 'buyer',
          'uploaded_at': '2026-08-01T09:00:00Z',
          'sha256': 'a' * 64,
          'note': null,
          'extraction_status': ?status,
        };

    test('reads whether the server managed to read the document', () {
      expect(evidenceFromRow(evidenceRow(status: 'extracted')).extractionStatus,
          ExtractionStatus.extracted);
      expect(evidenceFromRow(evidenceRow(status: 'unsupported')).extractionStatus,
          ExtractionStatus.unsupported);
      expect(evidenceFromRow(evidenceRow(status: 'failed')).extractionStatus,
          ExtractionStatus.failed);
    });

    test('counts extracted and truncated as read, and nothing else', () {
      expect(ExtractionStatus.extracted.wasRead, isTrue);
      expect(ExtractionStatus.truncated.wasRead, isTrue);
      for (final status in [
        ExtractionStatus.unsupported,
        ExtractionStatus.failed,
        ExtractionStatus.notAttempted,
      ]) {
        expect(status.wasRead, isFalse, reason: status.name);
      }
    });

    test('treats a row with no status as never attempted', () {
      // Rows filed before extraction existed. Not a judgement about the file.
      expect(evidenceFromRow(evidenceRow()).extractionStatus, ExtractionStatus.notAttempted);
    });

    test('refuses a status this build does not know', () {
      expect(() => evidenceFromRow(evidenceRow(status: 'ocr_pending')),
          throwsA(isA<RowMappingException>()));
    });

    test('tells a person something they can act on only when there is something', () {
      // An image having no text is not the reader's problem. A file that
      // should have been readable is, and only they can fix it.
      expect(unreadableNote(ExtractionStatus.failed), contains('file them as text'));
      expect(unreadableNote(ExtractionStatus.unsupported), contains('cannot read this kind of file'));
      expect(unreadableNote(ExtractionStatus.unsupported),
          isNot(contains('file them as text')));
    });
  });

  group('reading a proposal off its rows', () {
    Map<String, dynamic> proposalRow({num confidence = 0.8}) => {
          'id': 'p1',
          'decision': 'split',
          'summary': 'Part of the work met the brief.',
          'seller_amount_fils': 30000,
          'buyer_amount_fils': 20000,
          'confidence': confidence,
        };

    test('keeps findings in the order the server stored them', () {
      final proposal = proposalFromRows(
        proposalRow(),
        [
          {'id': 'f2', 'position': 1, 'statement': 'second'},
          {'id': 'f1', 'position': 0, 'statement': 'first'},
        ],
        [],
        [],
      );
      expect([for (final f in proposal!.findings) f.statement], ['first', 'second']);
    });

    test('attaches each citation to the finding that made it', () {
      final proposal = proposalFromRows(
        proposalRow(),
        [
          {'id': 'f1', 'position': 0, 'statement': 'first'},
          {'id': 'f2', 'position': 1, 'statement': 'second'},
        ],
        [
          {'finding_id': 'f1', 'evidence_id': 'e1'},
          {'finding_id': 'f2', 'evidence_id': 'e1'},
          {'finding_id': 'f2', 'evidence_id': 'e2'},
        ],
        [],
      );
      expect(proposal!.findings[0].evidenceIds, ['e1']);
      expect(proposal.findings[1].evidenceIds, ['e1', 'e2']);
    });

    test('reads which roles have accepted, and closes only when both have', () {
      final one = proposalFromRows(proposalRow(), [], [], [
        {'proposal_id': 'p1', 'role': 'buyer'},
      ]);
      expect(one!.bothAccepted, isFalse);

      final both = proposalFromRows(proposalRow(), [], [], [
        {'proposal_id': 'p1', 'role': 'buyer'},
        {'proposal_id': 'p1', 'role': 'seller'},
      ]);
      expect(both!.bothAccepted, isTrue);
    });

    test('conserves the split it was given', () {
      final proposal = proposalFromRows(proposalRow(), [], [], []);
      expect(proposal!.sellerAmount.value + proposal.buyerAmount.value, 50000);
    });

    test('refuses an AI proposal with no confidence, which the schema forbids', () {
      final row = proposalRow()..remove('confidence');
      expect(() => proposalFromRows(row, [], [], []), throwsA(isA<RowMappingException>()));
    });

    test('reads a reviewer decision, which has no confidence by design', () {
      // The other half of the same schema rule. Requiring a confidence here
      // would refuse every human decision, and inventing one would tell the
      // parties a reviewer was 80% sure of something they never scored.
      final row = proposalRow()
        ..['source'] = 'human'
        ..['confidence'] = null;
      final proposal = proposalFromRows(row, [], [], []);
      expect(proposal!.source, ProposalSource.human);
      expect(proposal.confidence, isNull);
    });

    test('treats a row with no source as the model, which is what older rows are', () {
      expect(proposalFromRows(proposalRow(), [], [], [])!.source, ProposalSource.ai);
    });

    test('refuses a source this build does not know', () {
      final row = proposalRow()..['source'] = 'arbitration';
      expect(() => proposalFromRows(row, [], [], []), throwsA(isA<RowMappingException>()));
    });

    test('is null when there is no proposal, rather than an empty one', () {
      expect(proposalFromRows(null, [], [], []), isNull);
    });
  });

  group('reading a dispute off its rows', () {
    test('treats an empty counter-claim as no answer at all', () {
      // The other side not having answered and the other side answering with
      // whitespace should read the same way to every screen.
      final dispute = disputeFromRows({
        'id': 'd1',
        'state': 'open',
        'opened_by_role': 'buyer',
        'buyer_claim': 'Only two concepts arrived.',
        'seller_claim': '   ',
      }, null);
      expect(dispute!.sellerClaim, isNull);
    });

    test('keeps a real counter-claim', () {
      final dispute = disputeFromRows({
        'id': 'd1',
        'state': 'open',
        'opened_by_role': 'buyer',
        'buyer_claim': 'a',
        'seller_claim': 'b',
      }, null);
      expect(dispute!.sellerClaim, 'b');
    });
  });

  group('describing an event', () {
    test('names the side that acted', () {
      expect(describeEvent(TransactionEvent.accept, Actor.seller), contains('seller'));
      expect(describeEvent(TransactionEvent.accept, Actor.buyer), contains('buyer'));
    });

    test('names TrustIQ for a system move, never a party', () {
      // A party must never appear to have done something the system did: the
      // whole point of the dispute design is that the AI proposes and the
      // parties decide.
      final text = describeEvent(TransactionEvent.resolveDispute, Actor.system);
      expect(text, contains('TrustIQ'));
      expect(text, isNot(contains('buyer')));
      expect(text, isNot(contains('seller')));
    });

    test('covers every event with a sentence, not a wire name', () {
      // The switch is exhaustive, so a new event stops this compiling rather
      // than reaching a screen as `mark_delivered`.
      for (final event in TransactionEvent.values) {
        final text = describeEvent(event, Actor.buyer);
        expect(text, isNot(equals(event.wireName)), reason: event.name);
        expect(text.split(' ').length, greaterThan(2), reason: event.name);
      }
    });
  });
}
