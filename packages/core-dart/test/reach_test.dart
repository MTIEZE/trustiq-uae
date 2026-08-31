import 'package:test/test.dart';
import 'package:trustiq_core/trustiq_core.dart';

void main() {
  test('a dispute is not gone, it is later', () {
    final later = comingLaterFor(TransactionState.pendingAcceptance, Actor.buyer);
    expect(later[TransactionEvent.openDispute], TransactionState.active,
        reason: 'the soonest state that allows it, not whichever row came first');
  });

  test('a finished contract promises nothing', () {
    expect(comingLaterFor(TransactionState.completed, Actor.buyer), isEmpty);
    expect(comingLaterFor(TransactionState.expired, Actor.seller), isEmpty);
  });

  test('what is possible now is not also listed as coming later', () {
    for (final state in TransactionState.values) {
      final now = availableEventsFor(state, Actor.buyer).toSet();
      final later = comingLaterFor(state, Actor.buyer).keys.toSet();
      expect(now.intersection(later), isEmpty, reason: state.name);
    }
  });

  test('nothing is promised that the actor could never do', () {
    for (final state in TransactionState.values) {
      for (final entry in comingLaterFor(state, Actor.seller).entries) {
        expect(canTransition(entry.value, entry.key, Actor.seller), isTrue,
            reason: '${entry.key.name} from ${entry.value.name}');
        expect(reachableFrom(state), contains(entry.value));
      }
    }
  });
}
