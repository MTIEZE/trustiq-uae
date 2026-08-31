import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/backend.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/verify_identity_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/language_button.dart';

/// The verification journey.
///
/// What stood here was one screen that could say two things: verified, or an
/// explanation and an email address. Four states were always real and the app
/// could not tell them apart, and the pair it confused worst was "never asked"
/// and "was refused": somebody turned down had no way to learn it, and nothing
/// to act on.
void main() {
  Widget host(AppState state) => MaterialApp(
        theme: buildTheme(TrustIqPalette.light),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: LanguageScope(
          controller: LanguageController.forTests(),
          // Keyed on the state. Pumping a second tree of the same type at the
          // same position reuses the element, so initState never runs again
          // and the new state is never read. Only a test does that, but a test
          // that silently keeps the old state proves nothing.
          child: VerifyIdentityScreen(key: ValueKey(state), state: state),
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  late L l;
  setUpAll(() async => l = await L.delegate.load(const Locale('en')));

  testWidgets('somebody who has never asked is given something to press', (tester) async {
    tall(tester);
    final backend = _Standing(MyVerification.unknown);
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text(l.verifyStartTitle), findsOneWidget);
    expect(find.text(l.verifySubmit), findsOneWidget);
    expect(find.text(l.verifyPendingTitle), findsNothing);
  });

  testWidgets('the form refuses to send without a name on the document', (tester) async {
    tall(tester);
    final backend = _Standing(MyVerification.unknown);
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.verifySubmit));
    await tester.pumpAndSettle();

    expect(find.text(l.verifyLegalNameMissing), findsOneWidget);
    expect(backend.asked, isEmpty, reason: 'nothing should have reached the server');
  });

  testWidgets('filling it in puts the person in the queue', (tester) async {
    tall(tester);
    final backend = _Standing(MyVerification.unknown);
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Mohamed Al Rashid');
    await tester.tap(find.text(l.verifyDocPassport));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.verifySubmit));
    await tester.pumpAndSettle();

    expect(backend.asked.length, 1);
    expect(backend.asked.single.legalName, 'Mohamed Al Rashid');
    expect(backend.asked.single.kind, DocumentKind.passport,
        reason: 'the chip that was chosen is the one that was sent');

    // Read back from the server rather than assumed. The server decides the
    // state, and it is the only thing that knows whether a request that looked
    // like it worked put somebody in the queue.
    expect(find.text(l.verifyPendingTitle), findsOneWidget);
    expect(find.text(l.verifySubmit), findsNothing);
  });

  testWidgets('a waiting request can be withdrawn, which is not a refusal', (tester) async {
    tall(tester);
    final backend = _Standing(MyVerification(
      standing: VerificationStanding.pending,
      since: DateTime(2026, 8, 30),
      documentKind: DocumentKind.emiratesId,
    ));
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text(l.verifyPendingTitle), findsOneWidget);
    expect(find.textContaining(l.verifyDocEmiratesId), findsWidgets);

    await tester.tap(find.text(l.verifyWithdraw));
    await tester.pumpAndSettle();

    expect(backend.withdrawals, 1);
    expect(find.text(l.verifyStartTitle), findsOneWidget,
        reason: 'withdrawing puts them back where they started, not into refused');
  });

  testWidgets('a refusal shows the reason and lets them try again', (tester) async {
    tall(tester);
    const why = 'The passport photo page was cut off. Send one showing all four corners.';
    final backend = _Standing(MyVerification(
      standing: VerificationStanding.rejected,
      since: DateTime(2026, 8, 30),
      reason: why,
    ));
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text(l.verifyRejectedTitle), findsOneWidget);

    // The whole reason a refusal is recorded rather than silently ignored.
    expect(find.text(why), findsOneWidget,
        reason: 'a refusal with no visible reason is a dead end');

    expect(find.text(l.verifyAskAgain), findsOneWidget,
        reason: 'and it says "again", because it is not their first attempt');
    expect(find.text(l.verifySubmit), findsNothing);
  });

  testWidgets('somebody verified is told so and offered nothing to do', (tester) async {
    tall(tester);
    final backend = _Standing(MyVerification(
      standing: VerificationStanding.verified,
      since: DateTime(2026, 8, 1),
    ));
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text(l.verifyDoneTitle), findsOneWidget);
    expect(find.text(l.verifySubmit), findsNothing);
    expect(find.text(l.verifyWithdraw), findsNothing);
  });

  testWidgets('a request that fails says so', (tester) async {
    // The gap the first real user fell into. The screen only spoke on success,
    // so a refused request stopped the button spinning and changed nothing
    // else, which looks exactly like a button that does nothing.
    tall(tester);
    final backend = _Refuses('You are already verified.');
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Mohamed Al Rashid');
    await tester.tap(find.text(l.verifySubmit));
    await tester.pumpAndSettle();

    expect(find.text('You are already verified.'), findsOneWidget,
        reason: 'the server wrote that sentence for a person to read');
    expect(find.text(l.verifySent), findsNothing);
  });

  testWidgets('and so does one that could not reach the server', (tester) async {
    tall(tester);
    final backend = _Offline();
    await tester.pumpWidget(host(AppState(backend: backend)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Mohamed Al Rashid');
    await tester.tap(find.text(l.verifySubmit));
    await tester.pumpAndSettle();

    // Not the raw exception: that one put a project URL in a snackbar once.
    expect(find.text(l.noConnection), findsOneWidget);
  });

  testWidgets('the explanation gets out of the way once they have asked', (tester) async {
    tall(tester);

    final before = _Standing(MyVerification.unknown);
    await tester.pumpWidget(host(AppState(backend: before)));
    await tester.pumpAndSettle();
    expect(find.text(l.bindingBetweenVerified), findsOneWidget,
        reason: 'somebody deciding whether to ask should read why it matters');

    final after = _Standing(MyVerification(
      standing: VerificationStanding.pending,
      since: DateTime(2026, 8, 30),
    ));
    await tester.pumpWidget(host(AppState(backend: after)));
    await tester.pumpAndSettle();
    expect(find.text(l.bindingBetweenVerified), findsNothing,
        reason: 'somebody who has already asked came back to read the answer');
  });

  group('reading where you stand', () {
    test('a server that cannot be reached leaves them able to ask', () async {
      // Never optimistic. Guessing `verified` after a failure shows a badge
      // that exists nowhere but the screen, and walks the person into a refusal
      // further down with nothing to explain it.
      final state = AppState(backend: _Unreachable());
      await state.loadStanding();
      expect(state.standing.standing, VerificationStanding.none);
      expect(state.standing.canAsk, isTrue);
      expect(state.error, isNull, reason: 'and it is not shouted about either');
    });

    test('it is read once, not on every rebuild', () async {
      final backend = _Standing(MyVerification.unknown);
      final state = AppState(backend: backend);
      await state.loadStanding();
      await state.loadStanding();
      await state.loadStanding();
      expect(backend.reads, 1);

      await state.loadStanding(force: true);
      expect(backend.reads, 2, reason: 'unless something could have changed it');
    });
  });
}

class _Asked {
  _Asked(this.legalName, this.kind);
  final String legalName;
  final DocumentKind kind;
}

/// A backend holding one standing, which its own calls move.
class _Standing extends DemoBackend {
  _Standing(this._standing);

  MyVerification _standing;
  final List<_Asked> asked = [];
  int withdrawals = 0;
  int reads = 0;

  @override
  bool get canRecordVerification => false;

  @override
  Future<MyVerification> myVerification() async {
    reads += 1;
    return _standing;
  }

  @override
  Future<void> requestVerification({
    required String legalName,
    required DocumentKind documentKind,
    String? how,
  }) async {
    asked.add(_Asked(legalName, documentKind));
    _standing = MyVerification(
      standing: VerificationStanding.pending,
      since: DateTime(2026, 8, 31),
      documentKind: documentKind,
      legalName: legalName,
    );
  }

  @override
  Future<bool> withdrawVerificationRequest() async {
    withdrawals += 1;
    _standing = MyVerification.unknown;
    return true;
  }
}

/// Refuses the way the database does, with words meant for a person.
class _Refuses extends DemoBackend {
  _Refuses(this.why);
  final String why;

  @override
  bool get canRecordVerification => false;

  @override
  Future<MyVerification> myVerification() async => MyVerification.unknown;

  @override
  Future<void> requestVerification({
    required String legalName,
    required DocumentKind documentKind,
    String? how,
  }) async =>
      throw BackendException(why);
}

/// Fails the way a phone on a bad connection does.
class _Offline extends DemoBackend {
  @override
  bool get canRecordVerification => false;

  @override
  Future<MyVerification> myVerification() async => MyVerification.unknown;

  @override
  Future<void> requestVerification({
    required String legalName,
    required DocumentKind documentKind,
    String? how,
  }) async =>
      throw Exception('ClientException with SocketException: Failed host lookup');
}

class _Unreachable extends DemoBackend {
  @override
  bool get canRecordVerification => false;

  @override
  Future<MyVerification> myVerification() async =>
      throw Exception('Failed host lookup');
}
