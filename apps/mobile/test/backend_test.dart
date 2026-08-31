import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/backend.dart';
import 'package:trustiq_app/data/config.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/data/rows.dart';
import 'package:trustiq_app/theme.dart';
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

    testWidgets('tells a person something they can act on only when there is something',
        (tester) async {
      // An image having no text is not the reader's problem. A file that
      // should have been readable is, and only they can fix it. Checked in
      // both languages, because a translation that flattens the two would
      // undo the distinction without failing anything else.
      for (final locale in LanguageController.supported) {
        late L l;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: locale,
            home: Builder(builder: (context) {
              l = L.of(context);
              return const SizedBox();
            }),
          ),
        );
        final failed = unreadableNote(ExtractionStatus.failed, l);
        final unsupported = unreadableNote(ExtractionStatus.unsupported, l);
        expect(failed.trim(), isNotEmpty, reason: locale.languageCode);
        expect(unsupported.trim(), isNotEmpty, reason: locale.languageCode);
        expect(failed, isNot(unsupported), reason: locale.languageCode);
      }
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
    // These used to run in English only, because the sentence was built in
    // English only: describeEvent hardcoded it at the moment a row was parsed,
    // and the contract history stayed English however the app was set. Running
    // every event through both languages is what stops that coming back.
    for (final code in ['en', 'ar']) {
      test('$code: names the side that acted', () async {
        final l = await L.delegate.load(Locale(code));
        expect(describeEvent(TransactionEvent.accept, Actor.seller, l), contains(l.whoSeller));
        expect(describeEvent(TransactionEvent.accept, Actor.buyer, l), contains(l.whoBuyer));
      });

      test('$code: names TrustIQ for a system move, never a party', () async {
        // A party must never appear to have done something the system did: the
        // whole point of the dispute design is that the AI proposes and the
        // parties decide.
        final l = await L.delegate.load(Locale(code));
        final text = describeEvent(TransactionEvent.resolveDispute, Actor.system, l);
        expect(text, contains(l.whoSystem));
        expect(text, isNot(contains(l.whoBuyer)));
        expect(text, isNot(contains(l.whoSeller)));
      });

      test('$code: covers every event with a sentence, not a wire name', () async {
        // The switches are exhaustive, so a new event stops this compiling
        // rather than reaching a screen as `mark_delivered`.
        final l = await L.delegate.load(Locale(code));
        for (final event in TransactionEvent.values) {
          final text = describeEvent(event, Actor.buyer, l);
          expect(text, isNot(equals(event.wireName)), reason: event.name);
          expect(text.trim(), isNotEmpty, reason: event.name);
        }
        for (final event in DisputeEvent.values) {
          final text = describeDisputeEvent(event, Actor.buyer, l);
          expect(text, isNot(equals(event.wireName)), reason: event.name);
          expect(text.trim(), isNotEmpty, reason: event.name);
        }
      });
    }

    test('the Arabic rendering is actually in Arabic', () async {
      // The regression guard for the bug this group was rewritten over. The
      // brand is the one thing allowed to stay in Latin script.
      final l = await L.delegate.load(const Locale('ar'));
      final arabic = RegExp(r'[؀-ۿ]');
      for (final event in TransactionEvent.values) {
        expect(arabic.hasMatch(describeEvent(event, Actor.buyer, l)), isTrue,
            reason: event.name);
      }
      for (final event in DisputeEvent.values) {
        expect(arabic.hasMatch(describeDisputeEvent(event, Actor.buyer, l)), isTrue,
            reason: event.name);
      }
    });
  });

  group('a failure nobody can read', () {
    // Reported from a tester's phone in Cameroon: a DNS failure reached the
    // sign-in screen as the raw Dart exception, unreadable, and carrying the
    // project URL to somebody who had no reason to see it.
    const raw = "ClientException with SocketException: Failed host lookup: "
        "'ieccihxvmlapfuhbjuxf.supabase.co' (OS Error: No address associated "
        "with hostname, errno = 7), uri=https://ieccihxvmlapfuhbjuxf.supabase.co"
        "/auth/v1/token?grant_type=password";

    test('a lost connection is told as a lost connection', () async {
      final state = AppState(backend: _ThrowsRaw(Exception(raw)));
      await state.refresh();

      final l = await L.delegate.load(const Locale('en'));
      final failed = describeFailure(state, l);

      expect(failed, isNotNull);
      expect(failed!.title, l.noConnection);
      expect(state.error, isNull, reason: 'there is no sentence to show, only a kind');
    });

    test('and the project URL never reaches a screen', () async {
      final state = AppState(backend: _ThrowsRaw(Exception(raw)));
      await state.refresh();

      final l = await L.delegate.load(const Locale('en'));
      final shown = describeFailure(state, l)!;
      final text = '${shown.title} ${shown.detail}';

      expect(text, isNot(contains('supabase.co')));
      expect(text, isNot(contains('errno')));
      expect(text, isNot(contains('Exception')));
    });

    test('anything else is a failure, not a stack trace', () async {
      final state = AppState(backend: _ThrowsRaw(StateError('Bad state: no element')));
      await state.refresh();

      final l = await L.delegate.load(const Locale('en'));
      final shown = describeFailure(state, l)!;
      expect(shown.title, l.somethingWentWrong);
      expect('${shown.title} ${shown.detail}', isNot(contains('Bad state')));
    });

    test('a backend that had words of its own keeps them', () async {
      // BackendException carries a sentence written for a person. Replacing it
      // with a generic one would lose the only useful thing about it.
      final state = AppState(backend: _ThrowsRaw(BackendException('Sign in first.')));
      await state.refresh();

      final l = await L.delegate.load(const Locale('en'));
      expect(describeFailure(state, l)!.title, 'Sign in first.');
    });

    test('dismissing clears both kinds', () async {
      final state = AppState(backend: _ThrowsRaw(Exception(raw)));
      await state.refresh();
      expect(state.failure, isNotNull);

      state.clearError();
      final l = await L.delegate.load(const Locale('en'));
      expect(describeFailure(state, l), isNull);
    });
  });

  group('a stage of work', () {
    Milestone at({DateTime? delivered, DateTime? accepted}) => Milestone(
          id: 'm', title: 'Concepts', amount: Fils(1000),
          deliveredAt: delivered, acceptedAt: accepted,
        );

    final now = DateTime.now();

    test('the three states come out of the two timestamps', () {
      expect(at().waiting, isTrue);
      expect(at(delivered: now).delivered, isTrue);
      expect(at(delivered: now, accepted: now).accepted, isTrue);
    });

    test('and they never overlap', () {
      // Which matters because the row offers exactly one button, chosen by
      // these three. Two of them true at once is two buttons.
      for (final m in [at(), at(delivered: now), at(delivered: now, accepted: now)]) {
        final on = [m.waiting, m.delivered, m.accepted].where((x) => x).length;
        expect(on, 1, reason: 'delivered=${m.deliveredAt} accepted=${m.acceptedAt}');
      }
    });

    test('an accepted stage is not also delivered', () {
      // delivered means delivered and waiting to be looked at. Once accepted
      // there is nothing to look at, and a screen showing both would offer
      // the buyer a button to accept something they already accepted.
      expect(at(delivered: now, accepted: now).delivered, isFalse);
    });

    test('a stage sent back reads as not started again', () {
      // request_milestone_revision clears delivered_at, because the stage
      // genuinely is not delivered any more. The attempt is not lost: it is
      // in milestone_events, which this model does not carry.
      expect(at().waiting, isTrue);
    });
  });

  group('inviting somebody who is not here yet', () {
    Invitation at(DateTime expires, {DateTime? claimed, DateTime? revoked}) => Invitation(
          id: 'i', code: 'ABCD-EFGH', email: 'someone@example.ae',
          inviteeIs: Role.seller, description: 'Work', amount: Fils(1000),
          expiresAt: expires, claimedAt: claimed, revokedAt: revoked,
        );

    final future = DateTime.now().add(const Duration(days: 1));
    final past = DateTime.now().subtract(const Duration(days: 1));

    test('an invitation is open only while all three things are true', () {
      expect(at(future).open, isTrue);
      expect(at(past).open, isFalse);
      expect(at(future, claimed: DateTime.now()).open, isFalse);
      expect(at(future, revoked: DateTime.now()).open, isFalse);
    });

    test('the three ways it closes stay apart', () {
      // The screen says which one happened. Collapsing them into "not
      // available" would leave somebody wondering whether to send it again.
      expect(at(past).expired, isTrue);
      expect(at(past).claimed, isFalse);
      expect(at(future, claimed: DateTime.now()).claimed, isTrue);
      expect(at(future, revoked: DateTime.now()).revoked, isTrue);
      // A claimed invitation is not also expired, whatever the clock says.
      expect(at(past, claimed: DateTime.now()).expired, isFalse);
    });

    test('a missing counterparty reaches the screen as itself', () async {
      // It travels through AppState._guard, which turns a BackendException
      // into a banner. This one has to survive that, because the screen turns
      // it into an offer to invite them rather than a dead end.
      final state = AppState(backend: _NoSuchPersonBackend());

      await expectLater(
        state.createContract(
          description: 'Work', terms: 'Terms.', amount: Fils(1000),
          youAre: Role.buyer, counterparty: 'nobody@example.ae',
        ),
        throwsA(isA<CounterpartyHasNoAccount>()
            .having((e) => e.email, 'email', 'nobody@example.ae')),
      );

      expect(state.error, isNull,
          reason: 'it is an offer, not a failure, so nothing should be in the banner');
    });
  });

/// Stands in for a project where the address belongs to nobody.
  group('attendance', () {
    // The register exists so "how many people came back" has an answer that is
    // not a third-party tracker. What it must not become is a chatty one.

    test('the app says it is here once, however often the token is renewed', () async {
      final backend = _CountsPresence();
      final state = AppState(backend: backend);
      await state.start();

      expect(backend.calls, 1, reason: 'a launch marks the person present');

      // What a phone actually does: the session stream fires again every time
      // the access token is refreshed, which on a device left open is several
      // times a day.
      backend.renewToken();
      backend.renewToken();
      backend.renewToken();
      await Future<void>.delayed(Duration.zero);

      expect(backend.calls, 1,
          reason: 'a renewed token is not somebody opening the app again');

      state.dispose();
    });

    test('somebody who signs in later is still counted', () async {
      final backend = _CountsPresence(signedIn: false);
      final state = AppState(backend: backend);
      await state.start();

      expect(backend.calls, 0, reason: 'nobody is present before there is a session');

      backend.signInLater();
      await Future<void>.delayed(Duration.zero);

      expect(backend.calls, 1);
      state.dispose();
    });

    test('a register that is refused does not surface anything', () async {
      // The contract the interface states. If this ever throws, somebody
      // opening the app on a bad connection sees a failure about a counter.
      final backend = _PresenceRefused();
      final state = AppState(backend: backend);
      await state.start();
      await Future<void>.delayed(Duration.zero);

      expect(state.error, isNull);
      expect(state.failure, isNull);
      state.dispose();
    });
  });
}

/// Counts how many times the app said somebody was here, and lets a test drive
/// the session stream the way Supabase drives it.
class _CountsPresence extends DemoBackend {
  _CountsPresence({this.signedIn = true});

  final bool signedIn;
  int calls = 0;

  final _sessions = StreamController<BackendSession?>.broadcast();

  static const _who = BackendSession(
    userId: 'usr_you',
    email: 'you@example.ae',
    displayName: 'You',
  );

  BackendSession? _current;
  bool _started = false;

  @override
  BackendSession? get session {
    if (!_started) {
      _started = true;
      _current = signedIn ? _who : null;
    }
    return _current;
  }

  @override
  Stream<BackendSession?> get sessionChanges => _sessions.stream;

  void renewToken() => _sessions.add(_who);

  void signInLater() {
    _current = _who;
    _sessions.add(_who);
  }

  @override
  Future<void> recordActivity() async => calls += 1;
}

class _PresenceRefused extends DemoBackend {
  @override
  Future<void> recordActivity() async {
    // What a real one does not do. SupabaseBackend catches this itself; the
    // point here is that AppState does not let it out either.
    throw StateError('the register is unreachable');
  }
}

class _NoSuchPersonBackend extends DemoBackend {
  @override
  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
    List<DraftStage> stages = const [],
  }) async {
    throw CounterpartyHasNoAccount(counterpartyEmail);
  }
}

/// Throws whatever it was handed, the way the network layer does.
class _ThrowsRaw extends DemoBackend {
  _ThrowsRaw(this.thrown);
  final Object thrown;

  @override
  Future<List<Contract>> loadContracts() async => throw thrown;
}
