/// The transaction state machine, ported from
/// `packages/core/src/transaction-machine.ts`.
///
/// Every legal move is one row in [transitions]. Anything not in the table is
/// refused. The rows here must match the TypeScript table and the seeded rows
/// in `supabase/migrations/0003_transactions.sql`; the parity test fails if
/// they ever disagree.
library;

import 'types.dart';

class TransitionRule {
  const TransitionRule({
    required this.from,
    required this.event,
    required this.to,
    required this.actors,
    required this.describe,
  });

  final TransactionState from;
  final TransactionEvent event;
  final TransactionState to;

  /// Actors allowed to fire this event.
  final Set<Actor> actors;

  /// Plain-language description, surfaced in the audit log and in docs.
  final String describe;
}

const List<TransitionRule> transitions = [
  TransitionRule(
    from: TransactionState.draft,
    event: TransactionEvent.submit,
    to: TransactionState.pendingAcceptance,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The party who drafted the contract sends it to the other side.',
  ),
  TransitionRule(
    from: TransactionState.draft,
    event: TransactionEvent.withdraw,
    to: TransactionState.cancelled,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The drafting party abandons the contract before sending it.',
  ),
  TransitionRule(
    from: TransactionState.pendingAcceptance,
    event: TransactionEvent.accept,
    to: TransactionState.active,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The receiving party agrees to the terms.',
  ),
  TransitionRule(
    from: TransactionState.pendingAcceptance,
    event: TransactionEvent.decline,
    to: TransactionState.declined,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The receiving party refuses the terms.',
  ),
  TransitionRule(
    from: TransactionState.pendingAcceptance,
    event: TransactionEvent.withdraw,
    to: TransactionState.cancelled,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The sending party pulls the contract back before it is accepted.',
  ),
  TransitionRule(
    from: TransactionState.pendingAcceptance,
    event: TransactionEvent.expire,
    to: TransactionState.expired,
    actors: {Actor.system},
    describe: 'The acceptance deadline passed with no answer.',
  ),
  TransitionRule(
    from: TransactionState.active,
    event: TransactionEvent.markDelivered,
    to: TransactionState.delivered,
    actors: {Actor.seller},
    describe: 'The seller declares the work delivered.',
  ),
  TransitionRule(
    from: TransactionState.active,
    event: TransactionEvent.openDispute,
    to: TransactionState.disputed,
    actors: {Actor.buyer, Actor.seller},
    describe: 'Either party raises a problem before delivery is declared.',
  ),
  TransitionRule(
    from: TransactionState.active,
    event: TransactionEvent.cancelByAgreement,
    to: TransactionState.cancelled,
    actors: {Actor.system},
    describe: 'Both parties agreed to call the contract off.',
  ),
  TransitionRule(
    from: TransactionState.delivered,
    event: TransactionEvent.confirmDelivery,
    to: TransactionState.completed,
    actors: {Actor.buyer},
    describe: 'The buyer accepts the delivery.',
  ),
  TransitionRule(
    from: TransactionState.delivered,
    event: TransactionEvent.requestRevision,
    to: TransactionState.active,
    actors: {Actor.buyer},
    describe: 'The buyer sends the work back for changes.',
  ),
  TransitionRule(
    from: TransactionState.delivered,
    event: TransactionEvent.openDispute,
    to: TransactionState.disputed,
    actors: {Actor.buyer, Actor.seller},
    describe: 'Review broke down and a formal dispute is opened.',
  ),
  TransitionRule(
    from: TransactionState.disputed,
    event: TransactionEvent.resolveDispute,
    to: TransactionState.resolved,
    actors: {Actor.system},
    describe: 'The dispute reached a conclusion.',
  ),
];

final Map<String, TransitionRule> _index = {
  for (final rule in transitions) '${rule.from.name}::${rule.event.name}': rule,
};

/// Every event that is legal from a state, regardless of actor.
List<TransactionEvent> availableEvents(TransactionState state) =>
    transitions.where((r) => r.from == state).map((r) => r.event).toList();

/// Every event a specific actor may fire. Drives what the UI offers.
List<TransactionEvent> availableEventsFor(TransactionState state, Actor actor) =>
    transitions
        .where((r) => r.from == state && r.actors.contains(actor))
        .map((r) => r.event)
        .toList();

bool canTransition(TransactionState state, TransactionEvent event, Actor actor) {
  final rule = _index['${state.name}::${event.name}'];
  return rule != null && rule.actors.contains(actor);
}

/// Applies an event to a state.
///
/// The distinction between invalidTransition and actorNotPermitted matters: the
/// first is a bug or a stale client, the second is someone trying to act as the
/// other party and belongs in the audit log.
Result<TransactionState, TransitionError> applyEvent(
  TransactionState state,
  TransactionEvent event,
  Actor actor,
) {
  if (state.isTerminal) {
    return Err(TransitionError(
      code: TransitionErrorCode.terminalState,
      message: 'Transaction is ${state.wireName} and can no longer change.',
      from: state.wireName,
      event: event.wireName,
      actor: actor,
    ));
  }

  final rule = _index['${state.name}::${event.name}'];
  if (rule == null) {
    return Err(TransitionError(
      code: TransitionErrorCode.invalidTransition,
      message: '"${event.wireName}" is not a legal move from ${state.wireName}.',
      from: state.wireName,
      event: event.wireName,
      actor: actor,
    ));
  }

  if (!rule.actors.contains(actor)) {
    final allowed = rule.actors.map((a) => a.wireName).join(', ');
    return Err(TransitionError(
      code: TransitionErrorCode.actorNotPermitted,
      message: 'The ${actor.wireName} may not fire "${event.wireName}" '
          'from ${state.wireName}. Allowed: $allowed.',
      from: state.wireName,
      event: event.wireName,
      actor: actor,
    ));
  }

  return Ok(rule.to);
}

/// Whether each side has a verified identity.
class PartyVerification {
  const PartyVerification({
    required this.buyerVerified,
    required this.sellerVerified,
  });

  final bool buyerVerified;
  final bool sellerVerified;

  bool get bothVerified => buyerVerified && sellerVerified;
}

/// A contract only becomes binding between verified identities.
///
/// A guard on top of the transition table rather than a row in it: the move is
/// legal, the parties are not yet eligible to make it. The database enforces
/// the same rule inside `apply_transaction_event`, so a client that skipped
/// this would be refused there. It exists here so the app can explain the
/// situation rather than surface a raw failure after the fact.
///
/// Returns null when the event may proceed.
TransitionError? identityGate(
  TransactionEvent event,
  PartyVerification verification,
  Actor actor,
) {
  if (event != TransactionEvent.accept) return null;
  if (verification.bothVerified) return null;

  final missing = <String>[
    if (!verification.buyerVerified) 'buyer',
    if (!verification.sellerVerified) 'seller',
  ];

  return TransitionError(
    code: TransitionErrorCode.guardFailed,
    message: 'Both parties must have a verified identity before a contract '
        'becomes active. Not yet verified: ${missing.join(', ')}.',
    from: TransactionState.pendingAcceptance.wireName,
    event: event.wireName,
    actor: actor,
  );
}
