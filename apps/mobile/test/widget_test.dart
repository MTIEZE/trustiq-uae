import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/screens/contracts_screen.dart';
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
}

/// Mounts a screen the way main.dart does.
///
/// `ContractsScreen` reads its state at build time and is rebuilt by a
/// ListenableBuilder above it. A test that mounts it bare gets one frame and
/// then nothing, which looks exactly like a screen that failed to update.
Widget _hosted(AppState state) => MaterialApp(
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
