import 'package:test/test.dart';
import 'package:trustiq_core/src/dispute_machine.dart';
import 'package:trustiq_core/src/transaction_machine.dart';
import 'package:trustiq_core/src/types.dart';

const actors = Actor.values;

void main() {
  group('actor authorization', () {
    test('lets only the seller declare delivery', () {
      const state = TransactionState.active;
      const event = TransactionEvent.markDelivered;
      expect(applyEvent(state, event, Actor.seller).isOk, isTrue);
      expect(applyEvent(state, event, Actor.buyer).isOk, isFalse);
      expect(applyEvent(state, event, Actor.system).isOk, isFalse);
    });

    test('lets only the buyer confirm or send back a delivery', () {
      const state = TransactionState.delivered;
      expect(applyEvent(state, TransactionEvent.confirmDelivery, Actor.buyer).isOk, isTrue);
      expect(applyEvent(state, TransactionEvent.confirmDelivery, Actor.seller).isOk, isFalse);
      expect(applyEvent(state, TransactionEvent.requestRevision, Actor.buyer).isOk, isTrue);
      expect(applyEvent(state, TransactionEvent.requestRevision, Actor.seller).isOk, isFalse);
    });

    test('reserves expiry, resolution and mutual cancellation for the system', () {
      final systemOnly = <(TransactionState, TransactionEvent)>[
        (TransactionState.pendingAcceptance, TransactionEvent.expire),
        (TransactionState.disputed, TransactionEvent.resolveDispute),
        (TransactionState.active, TransactionEvent.cancelByAgreement),
      ];
      for (final pair in systemOnly) {
        final state = pair.$1;
        final event = pair.$2;
        final label = '${state.name}/${event.name}';
        expect(applyEvent(state, event, Actor.system).isOk, isTrue, reason: label);
        expect(applyEvent(state, event, Actor.buyer).isOk, isFalse, reason: label);
        expect(applyEvent(state, event, Actor.seller).isOk, isFalse, reason: label);
      }
    });

    test('lets either party open a dispute, before or after delivery', () {
      for (final state in [TransactionState.active, TransactionState.delivered]) {
        expect(applyEvent(state, TransactionEvent.openDispute, Actor.buyer).isOk, isTrue);
        expect(applyEvent(state, TransactionEvent.openDispute, Actor.seller).isOk, isTrue);
      }
    });

    test('reports what each actor can do from a state', () {
      final buyerCan = availableEventsFor(TransactionState.delivered, Actor.buyer)
          .map((e) => e.wireName)
          .toSet();
      expect(buyerCan, {'confirm_delivery', 'request_revision', 'open_dispute'});
      expect(
        availableEventsFor(TransactionState.delivered, Actor.seller),
        [TransactionEvent.openDispute],
      );
      expect(availableEventsFor(TransactionState.delivered, Actor.system), isEmpty);
    });
  });

  group('lifecycle walkthroughs', () {
    TransactionState walk(List<(TransactionEvent, Actor)> steps) {
      var state = TransactionState.draft;
      for (final step in steps) {
        state = applyEvent(state, step.$1, step.$2).unwrap();
      }
      return state;
    }

    test('completes the happy path', () {
      expect(
        walk([
          (TransactionEvent.submit, Actor.buyer),
          (TransactionEvent.accept, Actor.seller),
          (TransactionEvent.markDelivered, Actor.seller),
          (TransactionEvent.confirmDelivery, Actor.buyer),
        ]),
        TransactionState.completed,
      );
    });

    test('supports a revision round before completion', () {
      expect(
        walk([
          (TransactionEvent.submit, Actor.buyer),
          (TransactionEvent.accept, Actor.seller),
          (TransactionEvent.markDelivered, Actor.seller),
          (TransactionEvent.requestRevision, Actor.buyer),
          (TransactionEvent.markDelivered, Actor.seller),
          (TransactionEvent.confirmDelivery, Actor.buyer),
        ]),
        TransactionState.completed,
      );
    });

    test('routes a disputed delivery to resolution', () {
      expect(
        walk([
          (TransactionEvent.submit, Actor.buyer),
          (TransactionEvent.accept, Actor.seller),
          (TransactionEvent.markDelivered, Actor.seller),
          (TransactionEvent.openDispute, Actor.buyer),
          (TransactionEvent.resolveDispute, Actor.system),
        ]),
        TransactionState.resolved,
      );
    });

    test('expires an ignored contract', () {
      expect(
        walk([
          (TransactionEvent.submit, Actor.buyer),
          (TransactionEvent.expire, Actor.system),
        ]),
        TransactionState.expired,
      );
    });

    test('refuses to move once a contract is completed', () {
      final completed = walk([
        (TransactionEvent.submit, Actor.buyer),
        (TransactionEvent.accept, Actor.seller),
        (TransactionEvent.markDelivered, Actor.seller),
        (TransactionEvent.confirmDelivery, Actor.buyer),
      ]);
      final result = applyEvent(completed, TransactionEvent.openDispute, Actor.buyer);
      expect(result.isErr, isTrue);
      expect((result as Err).error.code, TransitionErrorCode.terminalState);
    });
  });

  group('dispute machine', () {
    test('agrees with the table for every state, event and actor', () {
      for (final state in DisputeState.values) {
        for (final event in DisputeEvent.values) {
          for (final actor in actors) {
            final result = applyDisputeEvent(state, event, actor);
            final matches =
                disputeTransitions.where((r) => r.from == state && r.event == event);
            final rule = matches.isEmpty ? null : matches.first;
            final label = '${state.name}/${event.name}/${actor.name}';

            if (state.isTerminal || rule == null || !rule.actors.contains(actor)) {
              expect(result.isErr, isTrue, reason: label);
            } else {
              expect(result.isOk, isTrue, reason: label);
              expect(result.unwrap(), rule.to, reason: label);
            }
          }
        }
      }
    });

    test('keeps canTransitionDispute consistent with applyDisputeEvent', () {
      for (final state in DisputeState.values) {
        for (final event in DisputeEvent.values) {
          for (final actor in actors) {
            final viaApply = applyDisputeEvent(state, event, actor).isOk;
            final viaCan =
                canTransitionDispute(state, event, actor) && !state.isTerminal;
            expect(viaCan, viaApply,
                reason: '${state.name}/${event.name}/${actor.name}');
          }
        }
      }
    });

    test('makes every declared state reachable from open', () {
      final reached = <DisputeState>{DisputeState.open};
      final queue = <DisputeState>[DisputeState.open];
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final rule in disputeTransitions.where((r) => r.from == current)) {
          if (reached.add(rule.to)) queue.add(rule.to);
        }
      }
      for (final state in DisputeState.values) {
        expect(reached.contains(state), isTrue, reason: state.name);
      }
    });

    test('never lets a party close a dispute by accepting alone', () {
      const state = DisputeState.proposalIssued;
      const event = DisputeEvent.acceptProposal;
      expect(applyDisputeEvent(state, event, Actor.buyer).isOk, isFalse);
      expect(applyDisputeEvent(state, event, Actor.seller).isOk, isFalse);
      expect(applyDisputeEvent(state, event, Actor.system).isOk, isTrue);
    });

    test('lets a single refusal escalate to a human', () {
      const state = DisputeState.proposalIssued;
      const event = DisputeEvent.rejectProposal;
      expect(applyDisputeEvent(state, event, Actor.buyer).unwrap(), DisputeState.escalated);
      expect(applyDisputeEvent(state, event, Actor.seller).unwrap(), DisputeState.escalated);
    });

    test('walks the fast path when both sides agree', () {
      var state = DisputeState.open;
      state = applyDisputeEvent(state, DisputeEvent.submitForAi, Actor.system).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.issueProposal, Actor.system).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.acceptProposal, Actor.system).unwrap();
      expect(state, DisputeState.accepted);
    });

    test('walks the escalation path to a human decision', () {
      var state = DisputeState.open;
      state = applyDisputeEvent(state, DisputeEvent.submitForAi, Actor.system).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.issueProposal, Actor.system).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.rejectProposal, Actor.seller).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.assignReviewer, Actor.system).unwrap();
      state = applyDisputeEvent(state, DisputeEvent.issueHumanResolution, Actor.system).unwrap();
      expect(state, DisputeState.resolvedByHuman);
    });
  });

  group('recordAcceptance', () {
    test('requires both sides before a dispute may close', () {
      final first = recordAcceptance({}, Role.buyer);
      expect(first.acceptedBy, {Role.buyer});
      expect(first.bothAccepted, isFalse);

      final second = recordAcceptance(first.acceptedBy, Role.seller);
      expect(second.bothAccepted, isTrue);
    });

    test('is idempotent, so a retried request cannot close a dispute alone', () {
      var outcome = recordAcceptance({}, Role.buyer);
      for (var i = 0; i < 5; i++) {
        outcome = recordAcceptance(outcome.acceptedBy, Role.buyer);
      }
      expect(outcome.acceptedBy, {Role.buyer});
      expect(outcome.bothAccepted, isFalse);
    });

    test('does not care which side accepts first', () {
      var acceptedBy = <Role>{};
      for (final role in [Role.seller, Role.buyer]) {
        acceptedBy = recordAcceptance(acceptedBy, role).acceptedBy;
      }
      expect(recordAcceptance(acceptedBy, Role.buyer).bothAccepted, isTrue);
    });

    test('does not mutate the set it was given', () {
      final original = {Role.buyer};
      recordAcceptance(original, Role.seller);
      expect(original, {Role.buyer});
    });
  });
}
