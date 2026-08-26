import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/main.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// These tests pin the one thing that would be easy to get wrong in the UI:
/// the buttons a person is offered are exactly what the shared state machine
/// allows for their role, and nothing about accepting a resolution lets one
/// party close a dispute alone.

void main() {
  testWidgets('the contract list renders and shows state in words', (tester) async {
    await tester.pumpWidget(const TrustIqApp());
    await tester.pumpAndSettle();

    expect(find.text('Contracts'), findsOneWidget);
    expect(find.text('Logo design for a startup'), findsOneWidget);
    // A state is shown as a phrase a person can read, never the wire value.
    expect(find.text('Disputed'), findsOneWidget);
    expect(find.text('pending_acceptance'), findsNothing);
  });

  testWidgets('a delivered contract offers the buyer and the seller different moves',
      (tester) async {
    final state = AppState();
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
    final state = AppState();
    for (final role in Role.values) {
      state.viewAs(role);
      for (final contract in state.contracts) {
        final offered = state.actionsFor(contract);
        expect(offered, isNot(contains(TransactionEvent.resolveDispute)));
        expect(offered, isNot(contains(TransactionEvent.cancelByAgreement)));
        // Whatever is offered must also be legal in the domain.
        for (final event in offered) {
          expect(canTransition(contract.state, event, state.actor), isTrue,
              reason: '${contract.state.name}/${event.name}/${role.name}');
        }
      }
    }
  });

  testWidgets('a closed contract offers nothing at all', (tester) async {
    final state = AppState();
    final completed =
        state.contracts.firstWhere((c) => c.state == TransactionState.completed);
    for (final role in Role.values) {
      state.viewAs(role);
      expect(state.actionsFor(completed), isEmpty);
    }
  });

  testWidgets('one party accepting does not close the dispute', (tester) async {
    final state = AppState();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);
    // Seeded with the seller already in; the buyer has not answered.
    expect(disputed.dispute!.proposal!.acceptedBy, {Role.seller});

    state.viewAs(Role.seller);
    state.acceptProposal(disputed.id); // idempotent, changes nothing
    var current = state.contractById(disputed.id);
    expect(current.dispute!.proposal!.acceptedBy, {Role.seller});
    expect(current.state, TransactionState.disputed);

    state.viewAs(Role.buyer);
    state.acceptProposal(disputed.id);
    current = state.contractById(disputed.id);
    expect(current.dispute!.proposal!.bothAccepted, isTrue);
    expect(current.dispute!.state, DisputeState.accepted);
    // Closing the dispute resolves the contract, fired as the system.
    expect(current.state, TransactionState.resolved);
    expect(current.timeline.last.actor, Actor.system);
  });

  testWidgets('either party refusing sends the case to a human', (tester) async {
    final state = AppState();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);

    state.viewAs(Role.buyer);
    state.rejectProposal(disputed.id);

    final current = state.contractById(disputed.id);
    expect(current.dispute!.state, DisputeState.escalated);
  });

  testWidgets('the proposed split adds up to the amount in dispute', (tester) async {
    final state = AppState();
    final disputed =
        state.contracts.firstWhere((c) => c.state == TransactionState.disputed);
    final proposal = disputed.dispute!.proposal!;

    expect(
      proposal.sellerAmount.value + proposal.buyerAmount.value,
      disputed.totalAmount.value,
    );
  });

  testWidgets('the dispute screen shows the evidence fingerprints', (tester) async {
    await tester.pumpWidget(const TrustIqApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logo design for a startup'));
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
