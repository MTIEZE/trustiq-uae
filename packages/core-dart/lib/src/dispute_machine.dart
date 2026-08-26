/// The dispute state machine, ported from
/// `packages/core/src/dispute-machine.ts`.
///
/// The product decision encoded here: the AI does not rule, it proposes. A
/// proposal only closes a dispute when BOTH parties accept it. A single refusal
/// escalates to a human.
library;

import 'types.dart';

class DisputeTransitionRule {
  const DisputeTransitionRule({
    required this.from,
    required this.event,
    required this.to,
    required this.actors,
    required this.describe,
  });

  final DisputeState from;
  final DisputeEvent event;
  final DisputeState to;
  final Set<Actor> actors;
  final String describe;
}

const List<DisputeTransitionRule> disputeTransitions = [
  DisputeTransitionRule(
    from: DisputeState.open,
    event: DisputeEvent.submitForAi,
    to: DisputeState.aiReview,
    actors: {Actor.system},
    describe: 'Claims and evidence are complete, so the case goes to the model.',
  ),
  DisputeTransitionRule(
    from: DisputeState.open,
    event: DisputeEvent.withdrawDispute,
    to: DisputeState.withdrawn,
    actors: {Actor.buyer, Actor.seller},
    describe: 'The party who opened the dispute drops it.',
  ),
  DisputeTransitionRule(
    from: DisputeState.aiReview,
    event: DisputeEvent.issueProposal,
    to: DisputeState.proposalIssued,
    actors: {Actor.system},
    describe: 'The model returned a resolution that passed validation.',
  ),
  DisputeTransitionRule(
    from: DisputeState.aiReview,
    event: DisputeEvent.escalate,
    to: DisputeState.escalated,
    actors: {Actor.system},
    describe: 'Confidence too low or amount above the automatic ceiling.',
  ),
  DisputeTransitionRule(
    from: DisputeState.proposalIssued,
    event: DisputeEvent.acceptProposal,
    to: DisputeState.accepted,
    actors: {Actor.system},
    describe: 'Both parties accepted. Fired only once the second acceptance lands.',
  ),
  DisputeTransitionRule(
    from: DisputeState.proposalIssued,
    event: DisputeEvent.rejectProposal,
    to: DisputeState.escalated,
    actors: {Actor.buyer, Actor.seller},
    describe: 'Either party refuses. One refusal is enough.',
  ),
  DisputeTransitionRule(
    from: DisputeState.escalated,
    event: DisputeEvent.assignReviewer,
    to: DisputeState.humanReview,
    actors: {Actor.system},
    describe: 'A human reviewer picks up the case.',
  ),
  DisputeTransitionRule(
    from: DisputeState.humanReview,
    event: DisputeEvent.issueHumanResolution,
    to: DisputeState.resolvedByHuman,
    actors: {Actor.system},
    describe: 'The reviewer issued a decision.',
  ),
];

final Map<String, DisputeTransitionRule> _index = {
  for (final rule in disputeTransitions)
    '${rule.from.name}::${rule.event.name}': rule,
};

bool canTransitionDispute(DisputeState state, DisputeEvent event, Actor actor) {
  final rule = _index['${state.name}::${event.name}'];
  return rule != null && rule.actors.contains(actor);
}

Result<DisputeState, TransitionError> applyDisputeEvent(
  DisputeState state,
  DisputeEvent event,
  Actor actor,
) {
  if (state.isTerminal) {
    return Err(TransitionError(
      code: TransitionErrorCode.terminalState,
      message: 'Dispute is ${state.wireName} and can no longer change.',
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

class AcceptanceOutcome {
  const AcceptanceOutcome({required this.acceptedBy, required this.bothAccepted});
  final Set<Role> acceptedBy;
  final bool bothAccepted;
}

/// Records one party accepting the current proposal.
///
/// Idempotent: the same role accepting twice does not count as two
/// acceptances, which matters because a retried request must never close a
/// dispute on one party's say-so.
AcceptanceOutcome recordAcceptance(Set<Role> acceptedBy, Role role) {
  final next = {...acceptedBy, role};
  return AcceptanceOutcome(
    acceptedBy: next,
    bothAccepted: next.contains(Role.buyer) && next.contains(Role.seller),
  );
}
