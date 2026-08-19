/// Core domain vocabulary, ported from `packages/core/src/types.ts`.
///
/// The enum members are named to match the TypeScript string unions and the
/// Postgres enums exactly; `wireName` is the value that crosses the boundary.
library;

enum Role {
  buyer,
  seller;

  String get wireName => name;
  Role get counterparty => this == Role.buyer ? Role.seller : Role.buyer;

  static Role fromWire(String value) =>
      Role.values.firstWhere((r) => r.wireName == value);
}

/// Who is attempting a transition. `system` covers timers, the AI pipeline and
/// reconciliation; it is never a user.
enum Actor {
  buyer,
  seller,
  system;

  String get wireName => name;

  static Actor fromWire(String value) =>
      Actor.values.firstWhere((a) => a.wireName == value);

  static Actor ofRole(Role role) =>
      role == Role.buyer ? Actor.buyer : Actor.seller;
}

enum TransactionState {
  draft,
  pendingAcceptance('pending_acceptance'),
  active,
  delivered,
  completed,
  disputed,
  resolved,
  declined,
  cancelled,
  expired;
  // ESCROW-V2: funding_pending and funds_held slot in after pendingAcceptance
  // once a licensed partner holds funds.

  const TransactionState([String? wire]) : _wire = wire;
  final String? _wire;
  String get wireName => _wire ?? name;

  static TransactionState fromWire(String value) =>
      TransactionState.values.firstWhere((s) => s.wireName == value);

  bool get isTerminal => const {
        TransactionState.completed,
        TransactionState.resolved,
        TransactionState.declined,
        TransactionState.cancelled,
        TransactionState.expired,
      }.contains(this);
}

enum TransactionEvent {
  submit,
  withdraw,
  accept,
  decline,
  expire,
  markDelivered('mark_delivered'),
  requestRevision('request_revision'),
  confirmDelivery('confirm_delivery'),
  openDispute('open_dispute'),
  resolveDispute('resolve_dispute'),
  cancelByAgreement('cancel_by_agreement');

  const TransactionEvent([String? wire]) : _wire = wire;
  final String? _wire;
  String get wireName => _wire ?? name;

  static TransactionEvent fromWire(String value) =>
      TransactionEvent.values.firstWhere((e) => e.wireName == value);
}

enum DisputeState {
  open,
  aiReview('ai_review'),
  proposalIssued('proposal_issued'),
  accepted,
  escalated,
  humanReview('human_review'),
  resolvedByHuman('resolved_by_human'),
  withdrawn;

  const DisputeState([String? wire]) : _wire = wire;
  final String? _wire;
  String get wireName => _wire ?? name;

  static DisputeState fromWire(String value) =>
      DisputeState.values.firstWhere((s) => s.wireName == value);

  bool get isTerminal => const {
        DisputeState.accepted,
        DisputeState.resolvedByHuman,
        DisputeState.withdrawn,
      }.contains(this);
}

enum DisputeEvent {
  submitForAi('submit_for_ai'),
  issueProposal('issue_proposal'),
  acceptProposal('accept_proposal'),
  rejectProposal('reject_proposal'),
  escalate,
  assignReviewer('assign_reviewer'),
  issueHumanResolution('issue_human_resolution'),
  withdrawDispute('withdraw_dispute');

  const DisputeEvent([String? wire]) : _wire = wire;
  final String? _wire;
  String get wireName => _wire ?? name;

  static DisputeEvent fromWire(String value) =>
      DisputeEvent.values.firstWhere((e) => e.wireName == value);
}

enum ResolutionDecision {
  releaseToSeller('release_to_seller'),
  refundToBuyer('refund_to_buyer'),
  split;

  const ResolutionDecision([String? wire]) : _wire = wire;
  final String? _wire;
  String get wireName => _wire ?? name;

  static ResolutionDecision fromWire(String value) =>
      ResolutionDecision.values.firstWhere((d) => d.wireName == value);
}

enum TransitionErrorCode {
  invalidTransition('INVALID_TRANSITION'),
  actorNotPermitted('ACTOR_NOT_PERMITTED'),
  terminalState('TERMINAL_STATE'),
  guardFailed('GUARD_FAILED');

  const TransitionErrorCode(this.wireName);
  final String wireName;
}

class TransitionError {
  const TransitionError({
    required this.code,
    required this.message,
    required this.from,
    required this.event,
    required this.actor,
  });

  final TransitionErrorCode code;
  final String message;
  final String from;
  final String event;
  final Actor actor;

  @override
  String toString() => '${code.wireName}: $message';
}

/// A plain result type. The domain never throws for outcomes a caller must
/// handle, such as a party attempting a move they are not allowed to make.
sealed class Result<T, E> {
  const Result();
  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T unwrap() => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>(:final error) => throw StateError('unwrap on Err: $error'),
      };
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;
}
