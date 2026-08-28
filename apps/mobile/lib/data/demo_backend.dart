import 'dart:typed_data';

import 'package:trustiq_core/trustiq_core.dart';

import 'backend.dart';
import 'demo_data.dart';
import 'evidence_service.dart';

/// The backend the app uses when it has been given no project.
///
/// Everything is in memory and nothing is recorded anywhere. It exists so the
/// app runs, and is clickable, and can be tested, with no configuration and no
/// network. It is also what the widget tests run against.
///
/// The transitions here go through `applyEvent` from the domain package, the
/// same table the server and the database enforce, so the demo cannot reach a
/// state the real system would refuse. What it does not have is anyone
/// checking: it trusts `viewingAs`, where the live backend derives the actor
/// from a verified session. That difference is why `isLive` exists and why
/// screens say plainly when they are showing demo data.
class DemoBackend implements Backend {
  DemoBackend() : _contracts = seedContracts() {
    _uploader = _RecordingUploader(
      InMemoryEvidenceUploader(() => _contracts),
      this,
    );
  }

  List<Contract> _contracts;
  late final EvidenceUploader _uploader;

  /// Which side the demo is acting as. The live backend has no equivalent:
  /// there, the actor comes from the session and cannot be chosen.
  Role viewingAs = Role.buyer;

  Actor get _actor => Actor.ofRole(viewingAs);

  @override
  String get label => 'demo data';

  @override
  bool get isLive => false;

  @override
  BackendSession? get session => const BackendSession(
        userId: 'usr_you',
        email: 'you@example.ae',
        displayName: 'You',
      );

  @override
  EvidenceUploader get uploader => _uploader;

  // The demo is always signed in as the same person, so the session never
  // changes and this emits nothing after the current value.
  @override
  Stream<BackendSession?> get sessionChanges => Stream<BackendSession?>.value(session);

  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      SignUpOutcome.signedIn;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<List<Contract>> loadContracts() async => List.unmodifiable(_contracts);

  Contract _byId(String id) => _contracts.firstWhere((c) => c.id == id);

  /// Adds a filed document to the contract it belongs to.
  ///
  /// Only the demo needs this. On the live backend the server wrote the row
  /// before the upload returned, and the next load picks it up; here nothing
  /// else would ever record it.
  void _recordEvidence(String contractId, EvidenceItem item) {
    final contract = _byId(contractId);
    _replace(contract.withEvidence([...contract.evidence, item]));
  }

  void _replace(Contract updated) {
    _contracts = [
      for (final c in _contracts) if (c.id == updated.id) updated else c,
    ];
  }

  @override
  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
    List<DraftStage> stages = const [],
  }) async {
    final me = Party(
      id: 'usr_you',
      name: youAre == Role.buyer ? 'Ahmed Al-Rashid' : 'Sara Design Studio',
      verified: true,
    );
    final them = Party(
      id: 'usr_counterparty_${_contracts.length}',
      name: counterpartyEmail,
      verified: false,
    );

    final contract = Contract(
      id: 'txn_${DateTime.now().microsecondsSinceEpoch}',
      reference: 'TIQ-2026-${(900 + _contracts.length).toString().padLeft(4, '0')}',
      state: TransactionState.draft,
      description: description,
      terms: terms,
      totalAmount: amount,
      buyer: youAre == Role.buyer ? me : them,
      seller: youAre == Role.seller ? me : them,
      createdAt: DateTime.now(),
    );

    _contracts = [contract, ..._contracts];
    viewingAs = youAre;
    return contract;
  }

  @override
  Future<TransitionError?> fire(String contractId, TransactionEvent event) async {
    final contract = _byId(contractId);
    final result = applyEvent(contract.state, event, _actor);

    switch (result) {
      case Err(:final error):
        return error;
      case Ok(value: final nextState):
        _replace(contract.copyWith(
          state: nextState,
          timeline: [
            ...contract.timeline,
            TimelineEntry(
              at: DateTime.now(),
              event: event,
              actor: _actor,
            ),
          ],
        ));
        return null;
    }
  }

  @override
  Future<TransitionError?> openDispute(String contractId, String claim) async {
    final contract = _byId(contractId);
    final result = applyEvent(contract.state, TransactionEvent.openDispute, _actor);
    if (result case Err(:final error)) return error;

    final isBuyer = viewingAs == Role.buyer;
    _replace(contract.copyWith(
      state: result.unwrap(),
      dispute: Dispute(
        id: 'dsp_${DateTime.now().microsecondsSinceEpoch}',
        // Opens at `open`, not at `ai_review`. The case only reaches the model
        // once the server has both sides and the evidence; the app does not
        // decide that and must not pretend the analysis has started.
        state: DisputeState.open,
        openedByRole: viewingAs,
        buyerClaim: isBuyer ? claim : '',
        sellerClaim: isBuyer ? null : claim,
      ),
      timeline: [
        ...contract.timeline,
        TimelineEntry(
          at: DateTime.now(),
          event: TransactionEvent.openDispute,
          actor: _actor,
        ),
      ],
    ));
    return null;
  }

  @override
  Future<void> submitCounterClaim(String contractId, String claim) async {
    final contract = _byId(contractId);
    final dispute = contract.dispute;
    if (dispute == null) return;

    _replace(contract.copyWith(
      dispute: Dispute(
        id: dispute.id,
        state: dispute.state,
        openedByRole: dispute.openedByRole,
        buyerClaim: viewingAs == Role.buyer ? claim : dispute.buyerClaim,
        sellerClaim: viewingAs == Role.seller ? claim : dispute.sellerClaim,
        proposal: dispute.proposal,
        escalationReason: dispute.escalationReason,
      ),
    ));
  }

  @override
  Future<void> acceptProposal(String contractId) async {
    final contract = _byId(contractId);
    final dispute = contract.dispute;
    final proposal = dispute?.proposal;
    if (dispute == null || proposal == null) return;

    final outcome = recordAcceptance(proposal.acceptedBy, viewingAs);
    final updated = ResolutionProposal(
      decision: proposal.decision,
      summary: proposal.summary,
      findings: proposal.findings,
      sellerAmount: proposal.sellerAmount,
      buyerAmount: proposal.buyerAmount,
      confidence: proposal.confidence,
      source: proposal.source,
      acceptedBy: outcome.acceptedBy,
    );

    if (!outcome.bothAccepted) {
      _replace(contract.copyWith(
        dispute: Dispute(
          id: dispute.id,
          state: dispute.state,
          openedByRole: dispute.openedByRole,
          buyerClaim: dispute.buyerClaim,
          sellerClaim: dispute.sellerClaim,
          proposal: updated,
        ),
      ));
      return;
    }

    // Both sides are in. The system, not either party, closes the dispute and
    // resolves the contract.
    _replace(contract.copyWith(
      state: applyEvent(contract.state, TransactionEvent.resolveDispute, Actor.system).unwrap(),
      dispute: Dispute(
        id: dispute.id,
        state: applyDisputeEvent(dispute.state, DisputeEvent.acceptProposal, Actor.system).unwrap(),
        openedByRole: dispute.openedByRole,
        buyerClaim: dispute.buyerClaim,
        sellerClaim: dispute.sellerClaim,
        proposal: updated,
      ),
      timeline: [
        ...contract.timeline,
        TimelineEntry(
          at: DateTime.now(),
          event: TransactionEvent.resolveDispute,
          actor: Actor.system,
        ),
      ],
    ));
  }

  @override
  Future<void> rejectProposal(String contractId) async {
    final contract = _byId(contractId);
    final dispute = contract.dispute;
    if (dispute == null) return;

    final next = applyDisputeEvent(dispute.state, DisputeEvent.rejectProposal, _actor);
    if (next case Ok(value: final state)) {
      _replace(contract.copyWith(
        dispute: Dispute(
          id: dispute.id,
          state: state,
          openedByRole: dispute.openedByRole,
          buyerClaim: dispute.buyerClaim,
          sellerClaim: dispute.sellerClaim,
          proposal: dispute.proposal,
          escalationReason:
              '${viewingAs == Role.buyer ? 'The buyer' : 'The seller'} refused the proposal',
        ),
      ));
    }
  }

  final _invitations = <Invitation>[];
  var _codeSeed = 0;

  @override
  Future<Invitation> inviteCounterparty({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  }) async {
    _codeSeed += 1;
    final invitation = Invitation(
      id: 'inv_$_codeSeed',
      code: 'DEMO-${_codeSeed.toString().padLeft(4, '0')}',
      email: counterpartyEmail,
      inviteeIs: youAre == Role.buyer ? Role.seller : Role.buyer,
      description: description,
      amount: amount,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    _invitations.add(invitation);
    return invitation;
  }

  @override
  Future<String> claimInvitation(String code) async {
    // Deliberately permissive: the demo has one person in it, so refusing a
    // code because it was not addressed to you would make the flow
    // impossible to show. The live backend checks both the code and the
    // address, and the schema tests pin that.
    final at = _invitations.indexWhere(
      (i) => i.code.toUpperCase() == code.trim().toUpperCase() && i.open,
    );
    if (at == -1) throw BackendException('No open invitation with that code.');
    throw BackendException(
      'Claiming a code needs a real project. On demo data there is only one '
      'person, and both sides of a contract cannot be them.',
    );
  }

  @override
  Future<List<Invitation>> myInvitations() async =>
      List.unmodifiable(_invitations.reversed);

  @override
  Future<void> revokeInvitation(String id) async {
    final at = _invitations.indexWhere((i) => i.id == id);
    if (at == -1) throw BackendException('No such invitation.');
    final was = _invitations[at];
    _invitations[at] = Invitation(
      id: was.id,
      code: was.code,
      email: was.email,
      inviteeIs: was.inviteeIs,
      description: was.description,
      amount: was.amount,
      expiresAt: was.expiresAt,
      revokedAt: DateTime.now(),
    );
  }

  // The demo has one person in it, so there is nobody to be told anything by.
  // An empty list is the honest answer rather than invented activity.
  @override
  Future<List<AppNotification>> notifications({int limit = 50}) async => const [];

  @override
  Future<void> markNotificationsRead(DateTime before) async {}

  // The demo is one person looking at fixed data, so a stage that moved would
  // have to be invented rather than recorded. Refused with the reason instead.
  @override
  Future<void> deliverMilestone(String milestoneId) async =>
      throw BackendException('Stages move against a real project, not on demo data.');

  @override
  Future<void> acceptMilestone(String milestoneId) async =>
      throw BackendException('Stages move against a real project, not on demo data.');

  @override
  Future<void> requestMilestoneRevision(String milestoneId) async =>
      throw BackendException('Stages move against a real project, not on demo data.');

  @override
  Future<void> setPreferredLocale(String code) async {}

  @override
  bool get canRecordVerification => true;

  @override
  Future<void> recordVerification(Role role) async {
    // Verification belongs to a person, not to one contract, so it lands on
    // every contract they are on rather than only the one they were looking at.
    _contracts = [
      for (final c in _contracts)
        c.withParties(
          buyer: role == Role.buyer ? _verified(c.buyer) : c.buyer,
          seller: role == Role.seller ? _verified(c.seller) : c.seller,
        ),
    ];
  }

  static Party _verified(Party party) =>
      Party(id: party.id, name: party.name, verified: true);
}


/// Files through the in-memory uploader, then remembers the result.
///
/// The two halves are separate because they answer to different rules. The
/// uploader mirrors the server: it computes the digest itself and refuses what
/// the server would refuse. Storing the outcome is bookkeeping the demo has to
/// do for itself, and keeping it out of the uploader means the uploader can
/// still be read as a stand-in for the real one.
class _RecordingUploader implements EvidenceUploader {
  _RecordingUploader(this._inner, this._backend);

  final EvidenceUploader _inner;
  final DemoBackend _backend;

  @override
  Future<EvidenceUploadResult> upload({
    required String contractId,
    required Role uploaderRole,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  }) async {
    final result = await _inner.upload(
      contractId: contractId,
      uploaderRole: uploaderRole,
      filename: filename,
      contentType: contentType,
      bytes: bytes,
      note: note,
    );
    if (result is EvidenceUploaded) {
      _backend._recordEvidence(contractId, result.item);
    }
    return result;
  }
}
