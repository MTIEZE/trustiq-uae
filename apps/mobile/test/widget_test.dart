import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/backend.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/onboarding.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/contracts_screen.dart';
import 'package:trustiq_app/screens/activity_screen.dart';
import 'package:trustiq_app/screens/onboarding_screen.dart';
import 'package:trustiq_app/screens/verify_identity_screen.dart';
import 'package:trustiq_app/main.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// These tests pin the one thing that would be easy to get wrong in the UI:
/// the buttons a person is offered are exactly what the shared state machine
/// allows for their role, and nothing about accepting a resolution lets one
/// party close a dispute alone.

void main() {
  testWidgets('an empty list invites the first contract rather than reporting nothing', (tester) async {
    // A person who has just signed up sees this before anything else, so it
    // says what to do rather than that there is nothing to see.
    final state = AppState(backend: _EmptyBackend());
    await state.refresh();
    await tester.pumpWidget(_hosted(state));
    await tester.pumpAndSettle();

    expect(find.text('No contracts yet'), findsOneWidget);
    expect(find.textContaining('Both sides sign'), findsOneWidget);
  });

  testWidgets('a list still loading is not an empty list', (tester) async {
    // The two used to render the same, which tells a returning person their
    // contracts are gone for as long as the fetch takes. The backend here
    // finishes exactly when this test says so, which is the only way to
    // observe the moment in between.
    final backend = _PausedBackend();
    final state = AppState(backend: backend);
    unawaited(state.refresh());
    await tester.pumpWidget(_hosted(state));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No contracts yet'), findsNothing);

    backend.finish(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contracts yet'), findsOneWidget);
  });

  testWidgets('the contract list renders and shows state in words', (tester) async {
    await tester.pumpWidget(TrustIqApp(backend: DemoBackend()));
    await tester.pumpAndSettle();

    expect(find.text('Contracts'), findsOneWidget);
    expect(find.text('Logo design for a startup'), findsOneWidget);
    // A state is shown as a phrase a person can read, never the wire value.
    expect(find.text('Disputed'), findsOneWidget);
    expect(find.text('pending_acceptance'), findsNothing);
  });

  testWidgets('a delivered contract offers the buyer and the seller different moves',
      (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    final delivered =
        state.contracts.firstWhere((c) => c.state == TransactionState.delivered);

    state.viewAs(Role.buyer);
    final buyerMoves = state.actionsFor(delivered).toSet();
    state.viewAs(Role.seller);
    final sellerMoves = state.actionsFor(delivered).toSet();

    // Confirming a delivery is the buyer's alone; the seller can only dispute.
    expect(buyerMoves, contains(TransactionEvent.confirmDelivery));
    expect(sellerMoves, isNot(contains(TransactionEvent.confirmDelivery)));
    expect(sellerMoves, {TransactionEvent.openDispute});
  });

  testWidgets('the screen never offers a system-only move', (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    for (final role in Role.values) {
      state.viewAs(role);
      for (final contract in state.contracts) {
        final offered = state.actionsFor(contract);
        expect(offered, isNot(contains(TransactionEvent.resolveDispute)));
        expect(offered, isNot(contains(TransactionEvent.cancelByAgreement)));
        // Whatever is offered must also be legal in the domain.
        for (final event in offered) {
          expect(canTransition(contract.state, event, state.actorOn(contract)), isTrue,
              reason: '${contract.state.name}/${event.name}/${role.name}');
        }
      }
    }
  });

  testWidgets('a closed contract offers nothing at all', (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    final completed =
        state.contracts.firstWhere((c) => c.state == TransactionState.completed);
    for (final role in Role.values) {
      state.viewAs(role);
      expect(state.actionsFor(completed), isEmpty);
    }
  });

  testWidgets('one party accepting does not close the dispute', (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);
    // Seeded with the seller already in; the buyer has not answered.
    expect(disputed.dispute!.proposal!.acceptedBy, {Role.seller});

    state.viewAs(Role.seller);
    await state.acceptProposal(disputed.id); // idempotent, changes nothing
    var current = state.contractById(disputed.id);
    expect(current.dispute!.proposal!.acceptedBy, {Role.seller});
    expect(current.state, TransactionState.disputed);

    state.viewAs(Role.buyer);
    await state.acceptProposal(disputed.id);
    current = state.contractById(disputed.id);
    expect(current.dispute!.proposal!.bothAccepted, isTrue);
    expect(current.dispute!.state, DisputeState.accepted);
    // Closing the dispute resolves the contract, fired as the system.
    expect(current.state, TransactionState.resolved);
    expect(current.timeline.last.actor, Actor.system);
  });

  testWidgets('either party refusing sends the case to a human', (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);

    state.viewAs(Role.buyer);
    await state.rejectProposal(disputed.id);

    final current = state.contractById(disputed.id);
    expect(current.dispute!.state, DisputeState.escalated);
  });

  testWidgets('the proposed split adds up to the amount in dispute', (tester) async {
    final state = AppState(backend: DemoBackend());
    // Contracts are loaded on demand now, not in the constructor.
    await state.refresh();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);
    final proposal = disputed.dispute!.proposal!;

    expect(
      proposal.sellerAmount.value + proposal.buyerAmount.value,
      disputed.totalAmount.value,
    );
  });

  testWidgets('the dispute screen shows the evidence fingerprints', (tester) async {
    await tester.pumpWidget(TrustIqApp(backend: DemoBackend()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logo design for a startup'));
    await tester.pumpAndSettle();

    // The dispute banner sits below the fold on a small surface, so scroll to
    // it before tapping. Tapping a widget that is off screen silently hits
    // whatever is in front of it.
    await tester.ensureVisible(find.text('Proposal issued'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proposal issued'));
    await tester.pumpAndSettle();

    expect(find.text('signed-brief.pdf'), findsOneWidget);
    expect(
      find.text('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
      findsOneWidget,
    );

    // The proposal sits below the fold, and the list builds lazily, so scroll
    // it into view before asserting on it.
    await tester.scrollUntilVisible(
      find.text('Accept this resolution'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // The proposal is framed as a proposal, with both answers available.
    expect(find.text('Accept this resolution'), findsOneWidget);
    expect(find.text('Refuse and ask for a human'), findsOneWidget);
  });
  testWidgets('a backend that cannot verify offers no button that would fail', (tester) async {
    // The live backend cannot record a verification: the schema refuses a
    // session that tries to verify itself. Until UAE Pass is connected, the
    // screen has to say who does it instead. Offering the button anyway would
    // mean telling someone their contract is blocked on their identity, and
    // then handing them a control that errors every time they press it.
    _tallSurface(tester);
    final state = AppState(backend: _CannotVerifyBackend());
    await tester.pumpWidget(_hostedScreen(VerifyIdentityScreen(state: state)));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));

    expect(find.text(l.verifiedByHand), findsOneWidget);
    expect(find.text(l.continueWith('UAE Pass')), findsNothing);
    expect(find.text(l.verifiedByHandRecord), findsOneWidget);
  });

  testWidgets('a backend that can verify still offers the button', (tester) async {
    // The demo path, which does record it. The branch has to fall the other
    // way here, or the test above would pass on a screen with no button at all.
    _tallSurface(tester);
    final state = AppState(backend: DemoBackend());
    await tester.pumpWidget(_hostedScreen(VerifyIdentityScreen(state: state)));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));

    expect(find.text(l.verifiedByHand), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
  });
  testWidgets('a first launch explains the product before asking for an account', (tester) async {
    // The problem this screen exists for: somebody installs an app they know
    // nothing about, and the first thing it does is ask them to create an
    // account. A sign-in form is a request for trust made before any has been
    // offered.
    await tester.pumpWidget(TrustIqApp(
      backend: DemoBackend(),
      onboarding: OnboardingGate.forTests(seen: false),
    ));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));
    expect(find.text(l.onboarding1Title), findsOneWidget);
    expect(find.text(l.contracts), findsNothing);
  });

  testWidgets('the introduction says what TrustIQ will not do, not only what it will',
      (tester) async {
    // The panel that earns the account. v1 never touches the money, and an
    // introduction that left that out would be selling something else.
    await tester.pumpWidget(TrustIqApp(
      backend: DemoBackend(),
      onboarding: OnboardingGate.forTests(seen: false),
    ));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(l.onboardingNext));
      await tester.pumpAndSettle();
    }
    expect(find.text(l.onboarding3Title), findsOneWidget);
  });

  testWidgets('finishing it hands over to the rest of the app, once', (tester) async {
    final gate = OnboardingGate.forTests(seen: false);
    await tester.pumpWidget(TrustIqApp(backend: DemoBackend(), onboarding: gate));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(l.onboardingNext));
      await tester.pumpAndSettle();
    }

    // The last panel offers a decision rather than another Next.
    expect(find.text(l.onboardingNext), findsNothing);
    expect(find.text(l.onboardingCreateAccount), findsOneWidget);

    await tester.tap(find.text(l.onboardingCreateAccount));
    await tester.pumpAndSettle();

    expect(find.text(l.contracts), findsOneWidget);
    expect(gate.seen, isTrue, reason: 'a second launch must not show it again');
  });

  testWidgets('a launch after the first goes straight in', (tester) async {
    await tester.pumpWidget(TrustIqApp(
      backend: DemoBackend(),
      onboarding: OnboardingGate.forTests(seen: true),
    ));
    await tester.pump();

    final l = await L.delegate.load(const Locale('en'));
    expect(find.text(l.contracts), findsOneWidget);
    expect(find.text(l.onboarding1Title), findsNothing);
  });

  testWidgets('opened for reference it closes rather than offering an account', (tester) async {
    // Reachable again from the sign-in screen and the contract list. An
    // explanation you can only ever see once is not documentation.
    await tester.pumpWidget(_hostedScreen(const OnboardingScreen()));
    await tester.pumpAndSettle();

    final l = await L.delegate.load(const Locale('en'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(l.onboardingNext));
      await tester.pumpAndSettle();
    }

    expect(find.text(l.onboardingDone), findsOneWidget);
    expect(find.text(l.onboardingCreateAccount), findsNothing);
    expect(find.text(l.onboardingSkip), findsNothing);
  });
  for (final code in ['en', 'ar']) {
    testWidgets('the introduction fits a small phone in $code', (tester) async {
      // 360x640 is the small end of what this will actually run on, and the
      // top bar carries four things in a row. Flutter throws on an overflow in
      // a test, so this is a real check rather than a screenshot somebody has
      // to remember to look at. Arabic runs too: the same row right to left,
      // with longer words in it.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: OnboardingScreen(onFinished: () {}, onSignIn: () {}),
      ));
      await tester.pumpAndSettle();

      final l = await L.delegate.load(Locale(code));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(l.onboardingNext));
        await tester.pumpAndSettle();
      }
      expect(find.text(l.onboardingCreateAccount), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('the badge counts what needs you, not everything that happened', (tester) async {
    // A badge that also counted news would be lit permanently, and a badge
    // that is always lit is one people stop reading.
    final state = AppState(backend: _NoisyBackend());
    await state.refresh();

    expect(state.activity.length, 3);
    expect(state.waitingOnYou, 1);
  });

  testWidgets('a notification already read stops counting', (tester) async {
    final state = AppState(backend: _NoisyBackend());
    await state.refresh();
    expect(state.waitingOnYou, 1);

    await state.markActivityRead();
    expect(state.waitingOnYou, 0,
        reason: 'opening the list is what clears it, not tapping each line');
  });

  testWidgets('the activity screen keeps tasks above news', (tester) async {
    _tallSurface(tester);
    final state = AppState(backend: _NoisyBackend());
    await state.refresh();

    await tester.pumpWidget(_hostedScreen(ActivityScreen(state: state)));
    await tester.pumpAndSettle();

    final l = await L.delegate.load(const Locale('en'));
    // SectionLabel renders its text uppercased, so the finder has to match
    // what is on screen rather than what was passed in.
    final needsYou = tester.getTopLeft(find.text(l.needsYou.toUpperCase())).dy;
    final news = tester.getTopLeft(find.text(l.history.toUpperCase())).dy;
    expect(needsYou, lessThan(news),
        reason: 'news above a task is a task somebody misses');
  });
}

/// Three things happened: one waiting on you, two for information.
class _NoisyBackend extends DemoBackend {
  var _read = false;

  @override
  Future<List<AppNotification>> notifications({int limit = 50}) async {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 3, contractId: 'c1', disputeId: null, aboutDispute: false,
        event: 'submit', actor: Actor.buyer, needsYou: true,
        at: now, readAt: _read ? now : null,
      ),
      AppNotification(
        id: 2, contractId: 'c1', disputeId: null, aboutDispute: false,
        event: 'accept', actor: Actor.seller, needsYou: false,
        at: now.subtract(const Duration(hours: 1)), readAt: _read ? now : null,
      ),
      AppNotification(
        id: 1, contractId: 'c1', disputeId: 'd1', aboutDispute: true,
        event: 'escalate', actor: Actor.system, needsYou: false,
        at: now.subtract(const Duration(hours: 2)), readAt: _read ? now : null,
      ),
    ];
  }

  @override
  Future<void> markNotificationsRead(DateTime before) async => _read = true;
}

/// Renders the whole screen at once.
///
/// The default test surface is shorter than this screen, and a ListView does
/// not build what is off it, so a finder would report a missing widget when
/// the widget is only below the fold.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Mounts a screen with only the delegates it needs, for screens that do not
/// depend on a ListenableBuilder above them.
Widget _hostedScreen(Widget screen) => MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: screen,
    );

/// Stands in for the live backend, which records no verification of its own.
class _CannotVerifyBackend extends DemoBackend {
  @override
  bool get canRecordVerification => false;
}

/// Mounts a screen the way main.dart does.
///
/// `ContractsScreen` reads its state at build time and is rebuilt by a
/// ListenableBuilder above it. A test that mounts it bare gets one frame and
/// then nothing, which looks exactly like a screen that failed to update.
Widget _hosted(AppState state) => MaterialApp(
      // The delegates come from main.dart in the app, so a test that mounts a
      // screen directly has to supply them or every label throws.
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: ListenableBuilder(
        listenable: state,
        builder: (_, _) => ContractsScreen(state: state),
      ),
    );

/// A backend with nothing in it, for the empty state.
class _EmptyBackend extends DemoBackend {
  @override
  Future<List<Contract>> loadContracts() async => const [];
}

/// A backend that answers only when the test tells it to.
///
/// A timed delay would need pumpAndSettle to wait it out, and the spinner
/// never settles, so the test would hang rather than fail. Holding the future
/// open makes the in-between state observable and the test deterministic.
class _PausedBackend extends DemoBackend {
  final _pending = Completer<List<Contract>>();

  void finish(List<Contract> contracts) => _pending.complete(contracts);

  @override
  Future<List<Contract>> loadContracts() => _pending.future;
}
