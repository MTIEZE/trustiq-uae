import 'package:test/test.dart';
import 'package:trustiq_core/src/transaction_machine.dart';
import 'package:trustiq_core/src/types.dart';

const actors = Actor.values;

void main() {
  group('transaction table integrity', () {
    test('has no duplicate (from, event) pairs', () {
      final seen = <String>{};
      for (final rule in transitions) {
        final key = '${rule.from.name}::${rule.event.name}';
        expect(seen.add(key), isTrue, reason: 'duplicate rule for $key');
      }
    });

    test('declares at least one actor per rule', () {
      for (final rule in transitions) {
        expect(rule.actors, isNotEmpty);
      }
    });

    test('gives every rule a plain-language description', () {
      for (final rule in transitions) {
        expect(rule.describe.trim(), isNotEmpty);
      }
    });

    test('never lets a terminal state transition out', () {
      for (final state in TransactionState.values.where((s) => s.isTerminal)) {
        expect(transitions.where((r) => r.from == state), isEmpty,
            reason: state.name);
      }
    });

    test('leaves no non-terminal state without a way out', () {
      for (final state in TransactionState.values.where((s) => !s.isTerminal)) {
        expect(availableEvents(state), isNotEmpty, reason: state.name);
      }
    });

    test('makes every declared state reachable from draft', () {
      final reached = <TransactionState>{TransactionState.draft};
      final queue = <TransactionState>[TransactionState.draft];
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final rule in transitions.where((r) => r.from == current)) {
          if (reached.add(rule.to)) queue.add(rule.to);
        }
      }
      for (final state in TransactionState.values) {
        expect(reached.contains(state), isTrue, reason: state.name);
      }
    });
  });

  group('applyEvent, exhaustively', () {
    test('agrees with the table for every state, event and actor', () {
      var allowed = 0;
      var refused = 0;

      for (final state in TransactionState.values) {
        for (final event in TransactionEvent.values) {
          for (final actor in actors) {
            final result = applyEvent(state, event, actor);
            final matches =
                transitions.where((r) => r.from == state && r.event == event);
            final rule = matches.isEmpty ? null : matches.first;
            final label = '${state.name}/${event.name}/${actor.name}';

            if (state.isTerminal) {
              expect(result.isErr, isTrue, reason: label);
              expect((result as Err).error.code,
                  TransitionErrorCode.terminalState, reason: label);
              refused++;
            } else if (rule == null) {
              expect(result.isErr, isTrue, reason: label);
              expect((result as Err).error.code,
                  TransitionErrorCode.invalidTransition, reason: label);
              refused++;
            } else if (!rule.actors.contains(actor)) {
              expect(result.isErr, isTrue, reason: label);
              expect((result as Err).error.code,
                  TransitionErrorCode.actorNotPermitted, reason: label);
              refused++;
            } else {
              expect(result.isOk, isTrue, reason: label);
              expect(result.unwrap(), rule.to, reason: label);
              allowed++;
            }
          }
        }
      }

      expect(allowed, greaterThan(0));
      expect(refused, greaterThan(0));
      expect(
          allowed + refused,
          TransactionState.values.length *
              TransactionEvent.values.length *
              actors.length);
    });

    test('keeps canTransition consistent with applyEvent', () {
      for (final state in TransactionState.values) {
        for (final event in TransactionEvent.values) {
          for (final actor in actors) {
            final viaApply = applyEvent(state, event, actor).isOk;
            final viaCan =
                canTransition(state, event, actor) && !state.isTerminal;
            expect(viaCan, viaApply,
                reason: '${state.name}/${event.name}/${actor.name}');
          }
        }
      }
    });
  });
  _identityGate();
}

void _identityGate() {
  group('the identity gate', () {
    const both = PartyVerification(buyerVerified: true, sellerVerified: true);

    test('lets an accept through when both parties are verified', () {
      expect(identityGate(TransactionEvent.accept, both, Actor.seller), isNull);
    });

    test('blocks an accept while either party is unverified', () {
      const cases = [
        PartyVerification(buyerVerified: false, sellerVerified: true),
        PartyVerification(buyerVerified: true, sellerVerified: false),
        PartyVerification(buyerVerified: false, sellerVerified: false),
      ];
      for (final verification in cases) {
        final error = identityGate(TransactionEvent.accept, verification, Actor.seller);
        expect(error, isNotNull);
        expect(error!.code, TransitionErrorCode.guardFailed);
      }
    });

    test('names who is missing, so the app can say something useful', () {
      const onlySeller = PartyVerification(buyerVerified: false, sellerVerified: true);
      final error = identityGate(TransactionEvent.accept, onlySeller, Actor.buyer);
      expect(error!.message, contains('buyer'));
    });

    test('gates nothing but accept', () {
      // Drafting, delivering and disputing stay open to an unverified party.
      const unverified = PartyVerification(buyerVerified: false, sellerVerified: false);
      for (final event in TransactionEvent.values) {
        if (event == TransactionEvent.accept) continue;
        expect(identityGate(event, unverified, Actor.buyer), isNull, reason: event.name);
      }
    });
  });
}
