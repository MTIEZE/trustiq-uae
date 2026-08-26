import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// The two flows that create data rather than move it along: making a contract
/// and opening a dispute. Both have a rule the UI could quietly get wrong, so
/// both are pinned here.

void main() {
  group('creating a contract', () {
    test('starts in draft, and only the creator can send it', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final contract = (await state.createContract(
        description: 'Website copy',
        terms: 'Nine hundred words, delivered in a Google Doc.',
        amount: filsFromAed('1200'),
        youAre: Role.buyer,
        counterparty: 'Layla Nasr',
      ))!;

      expect(contract.state, TransactionState.draft);
      expect(state.actionsFor(contract), contains(TransactionEvent.submit));
      // A draft cannot be accepted, delivered or disputed by anyone yet.
      expect(state.actionsFor(contract), isNot(contains(TransactionEvent.accept)));
      expect(state.actionsFor(contract), isNot(contains(TransactionEvent.markDelivered)));
    });

    test('records the amount exactly, with no float anywhere in the path', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      // 5.55 is the value that becomes 554.9999… under naive float maths.
      final contract = (await state.createContract(
        description: 'A small job',
        terms: 'Terms.',
        amount: filsFromAed('5.55'),
        youAre: Role.seller,
        counterparty: 'Someone',
      ))!;

      expect(contract.totalAmount.value, 555);
      expect(formatAed(contract.totalAmount), '5.55 AED');
    });

    test('puts the creator on the side they chose', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();

      final asBuyer = (await state.createContract(
        description: 'A',
        terms: 'T',
        amount: filsFromAed('10'),
        youAre: Role.buyer,
        counterparty: 'Them',
      ))!;
      expect(asBuyer.seller.name, 'Them');

      final asSeller = (await state.createContract(
        description: 'B',
        terms: 'T',
        amount: filsFromAed('10'),
        youAre: Role.seller,
        counterparty: 'Them',
      ))!;
      expect(asSeller.buyer.name, 'Them');
    });

    test('the new contract is the one at the top of the list', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final before = state.contracts.length;
      final created = (await state.createContract(
        description: 'Newest',
        terms: 'T',
        amount: filsFromAed('1'),
        youAre: Role.buyer,
        counterparty: 'Them',
      ))!;

      expect(state.contracts.length, before + 1);
      expect(state.contracts.first.id, created.id);
    });
  });

  group('opening a dispute', () {
    /// A contract in `delivered`, which is where a dispute realistically starts.
    Future<({AppState state, String id})> deliveredContract() async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final contract =
          state.contracts.firstWhere((c) => c.state == TransactionState.delivered);
      return (state: state, id: contract.id);
    }

    test('creates the dispute alongside the transition, never one without the other',
        () async {
      final (:state, :id) = await deliveredContract();
      state.viewAs(Role.buyer);

      final error = await state.openDispute(id, 'Two of the three deliverables are missing.');
      expect(error, isNull);

      final contract = state.contractById(id);
      expect(contract.state, TransactionState.disputed);
      // The bug this test exists for: a disputed contract with no dispute
      // attached is a state nothing downstream can read.
      expect(contract.dispute, isNotNull);
      expect(contract.dispute!.state, DisputeState.open);
    });

    test('files the claim under the role that wrote it', () async {
      final (:state, :id) = await deliveredContract();
      state.viewAs(Role.seller);
      await state.openDispute(id, 'The client stopped responding before final sign-off.');

      final dispute = state.contractById(id).dispute!;
      expect(dispute.openedByRole, Role.seller);
      expect(dispute.sellerClaim, contains('stopped responding'));
      expect(dispute.buyerClaim, isEmpty);
    });

    test('does not pretend the analysis has started', () async {
      // The app cannot know when the server hands the case to the model, so it
      // must not show a state implying it has.
      final (:state, :id) = await deliveredContract();
      state.viewAs(Role.buyer);
      await state.openDispute(id, 'A claim long enough to be worth reading.');

      final dispute = state.contractById(id).dispute!;
      expect(dispute.state, DisputeState.open);
      expect(dispute.state, isNot(DisputeState.aiReview));
      expect(dispute.proposal, isNull);
    });

    test('refuses on a contract where the domain does not allow it', () async {
      final state = AppState(backend: DemoBackend());
      // Contracts are loaded on demand now, not in the constructor.
      await state.refresh();
      final completed =
          state.contracts.firstWhere((c) => c.state == TransactionState.completed);

      final error = await state.openDispute(completed.id, 'A claim, submitted too late.');

      expect(error, isNotNull);
      expect(error!.code, TransitionErrorCode.terminalState);
      // Nothing was written.
      expect(state.contractById(completed.id).dispute, isNull);
      expect(state.contractById(completed.id).state, TransactionState.completed);
    });

    test('the other party can add their account without changing the state', () async {
      final (:state, :id) = await deliveredContract();
      state.viewAs(Role.buyer);
      await state.openDispute(id, 'The third concept is a colour variation, not a concept.');

      state.viewAs(Role.seller);
      await state.submitCounterClaim(id, 'Three distinct concepts were delivered on time.');

      final dispute = state.contractById(id).dispute!;
      expect(dispute.buyerClaim, contains('colour variation'));
      expect(dispute.sellerClaim, contains('Three distinct concepts'));
      expect(dispute.state, DisputeState.open);
      // Still the buyer's dispute, whoever answered it.
      expect(dispute.openedByRole, Role.buyer);
    });
  });
}
