
import 'package:flutter/foundation.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'data/demo_data.dart';
import 'data/evidence_service.dart';
import 'data/identity_provider.dart';

/// App state over the in-memory demo data.
///
/// Every state change goes through `applyEvent` from the domain package, the
/// same table the server and the database enforce. Nothing here decides for
/// itself whether a move is legal, so the app cannot offer a button the rest of
/// the system would refuse.
class AppState extends ChangeNotifier {
  AppState({EvidenceUploader? uploader, IdentityProvider? identityProvider})
      : _contracts = seedContracts() {
    _uploader = uploader ?? InMemoryEvidenceUploader(() => _contracts);
    _identity = identityProvider ?? const DemoIdentityProvider();
  }

  List<Contract> _contracts;
  late final EvidenceUploader _uploader;
  late final IdentityProvider _identity;

  /// Names the provider so a screen can say what it is sending someone to.
  String get identityProviderName => _identity.displayName;

  /// False while the real UAE Pass integration is not wired up. Screens use
  /// this to be honest about what verifying does and does not prove today.
  bool get identityProviderConnected => _identity is! DemoIdentityProvider;

  /// Which side of the contracts you are looking at.
  ///
  /// A demo affordance: the real app knows who you are from your session. It
  /// earns its place here because switching it shows, immediately, that the
  /// available actions belong to a role rather than to a screen.
  Role _viewingAs = Role.buyer;

  List<Contract> get contracts => List.unmodifiable(_contracts);
  Role get viewingAs => _viewingAs;
  Actor get actor => Actor.ofRole(_viewingAs);

  Contract contractById(String id) => _contracts.firstWhere((c) => c.id == id);

  void viewAs(Role role) {
    if (_viewingAs == role) return;
    _viewingAs = role;
    notifyListeners();
  }

  /// The events this actor may fire on this contract right now.
  List<TransactionEvent> actionsFor(Contract contract) =>
      availableEventsFor(contract.state, actor)
          // The system fires these off the back of other work; they are never
          // buttons a party presses.
          .where((e) => e != TransactionEvent.resolveDispute)
          .where((e) => e != TransactionEvent.cancelByAgreement)
          .toList();

  /// Whether each side of a contract has a verified identity.
  PartyVerification verificationFor(Contract contract) => PartyVerification(
        buyerVerified: contract.buyer.verified,
        sellerVerified: contract.seller.verified,
      );

  /// Why an action is blocked beyond the transition table, or null.
  ///
  /// Delegates to the shared guard rather than re-deciding here, so the app,
  /// the server and the database all answer the same question the same way.
  TransitionError? guardFor(Contract contract, TransactionEvent event) =>
      identityGate(event, verificationFor(contract), actor);

  /// Runs identity verification and marks you verified on success.
  Future<VerificationOutcome> verifyIdentity() async {
    final outcome = await _identity.verify(role: _viewingAs);
    if (outcome is VerificationSucceeded) {
      _markVerified(_viewingAs);
      notifyListeners();
    }
    return outcome;
  }

  /// Marks the given side verified everywhere they appear.
  ///
  /// Verification belongs to a person, not to one contract, so it lands on
  /// every contract they are on rather than only the one they were looking at.
  void _markVerified(Role role) {
    final me = _contracts
        .map((c) => c.partyFor(role))
        .where((p) => p.id == 'usr_you' || p.verified == false)
        .toList();
    if (me.isEmpty) return;

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

  /// Creates a contract in draft.
  ///
  /// The amount arrives as the text the person typed and is parsed by the
  /// domain, so a value the domain would refuse never becomes a contract.
  /// Nothing here rounds, and nothing here holds a double.
  Contract createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyName,
  }) {
    final me = Party(
      id: 'usr_you',
      name: youAre == Role.buyer ? 'Ahmed Al-Rashid' : 'Sara Design Studio',
      verified: true,
    );
    final them = Party(
      id: 'usr_counterparty_${_contracts.length}',
      name: counterpartyName,
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
    _viewingAs = youAre;
    notifyListeners();
    return contract;
  }

  /// Opens a dispute with the claim its author wrote.
  ///
  /// The contract transition and the dispute record are made together: a
  /// contract in `disputed` with no dispute attached would be a state the rest
  /// of the product cannot read.
  TransitionError? openDispute(String contractId, String claim) {
    final contract = contractById(contractId);
    final result = applyEvent(contract.state, TransactionEvent.openDispute, actor);

    if (result case Err(:final error)) return error;

    final nextState = result.unwrap();
    final isBuyer = _viewingAs == Role.buyer;

    _replace(contract.copyWith(
      state: nextState,
      dispute: Dispute(
        id: 'dsp_${DateTime.now().microsecondsSinceEpoch}',
        // Opens at `open`, not at `ai_review`. The case only reaches the model
        // once the server has both sides and the evidence; the app does not
        // decide that and must not pretend the analysis has started.
        state: DisputeState.open,
        openedByRole: _viewingAs,
        buyerClaim: isBuyer ? claim : '',
        sellerClaim: isBuyer ? null : claim,
      ),
      timeline: [
        ...contract.timeline,
        TimelineEntry(
          at: DateTime.now(),
          event: TransactionEvent.openDispute,
          actor: actor,
          describe: _describe(contract, TransactionEvent.openDispute),
        ),
      ],
    ));
    notifyListeners();
    return null;
  }

  /// The other party answering an open dispute.
  void submitCounterClaim(String contractId, String claim) {
    final contract = contractById(contractId);
    final dispute = contract.dispute;
    if (dispute == null) return;

    _replace(contract.copyWith(
      dispute: Dispute(
        id: dispute.id,
        state: dispute.state,
        openedByRole: dispute.openedByRole,
        buyerClaim: _viewingAs == Role.buyer ? claim : dispute.buyerClaim,
        sellerClaim: _viewingAs == Role.seller ? claim : dispute.sellerClaim,
        proposal: dispute.proposal,
        escalationReason: dispute.escalationReason,
      ),
    ));
    notifyListeners();
  }

  /// Files a document against a contract.
  ///
  /// The digest on the stored item is the uploader's, which stands in for the
  /// server here. The app never writes a fingerprint of its own into the
  /// record: whatever it could compute locally is a claim, and the value kept
  /// is the one computed from the bytes that were actually stored.
  Future<EvidenceUploadResult> fileEvidence({
    required String contractId,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  }) async {
    final result = await _uploader.upload(
      contractId: contractId,
      uploaderRole: _viewingAs,
      filename: filename,
      contentType: contentType,
      bytes: bytes,
      note: note,
    );

    if (result case EvidenceUploaded(:final item)) {
      final contract = contractById(contractId);
      _replace(contract.withEvidence([...contract.evidence, item]));
      notifyListeners();
    }
    return result;
  }

  /// Applies an event, or returns why the domain refused it.
  ///
  /// The refusal path is not dead code: it is what a stale screen hits when the
  /// counterparty moved first, and the person deserves the real reason.
  TransitionError? fire(String contractId, TransactionEvent event) {
    final contract = contractById(contractId);
    final result = applyEvent(contract.state, event, actor);

    switch (result) {
      case Err(:final error):
        return error;
      case Ok(value: final nextState):
        final entry = TimelineEntry(
          at: DateTime.now(),
          event: event,
          actor: actor,
          describe: _describe(contract, event),
        );
        _replace(contract.copyWith(
          state: nextState,
          timeline: [...contract.timeline, entry],
        ));
        notifyListeners();
        return null;
    }
  }

  /// Records this party accepting the current proposal.
  ///
  /// Idempotent, and the dispute closes only once both roles have accepted,
  /// exactly as `recordAcceptance` and the database define it.
  void acceptProposal(String contractId) {
    final contract = contractById(contractId);
    final dispute = contract.dispute;
    final proposal = dispute?.proposal;
    if (dispute == null || proposal == null) return;

    final outcome = recordAcceptance(proposal.acceptedBy, _viewingAs);
    final updatedProposal = ResolutionProposal(
      decision: proposal.decision,
      summary: proposal.summary,
      findings: proposal.findings,
      sellerAmount: proposal.sellerAmount,
      buyerAmount: proposal.buyerAmount,
      confidence: proposal.confidence,
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
          proposal: updatedProposal,
        ),
      ));
      notifyListeners();
      return;
    }

    // Both sides are in. The system, not either party, closes the dispute and
    // resolves the contract.
    final closedDispute = Dispute(
      id: dispute.id,
      state: applyDisputeEvent(
        dispute.state,
        DisputeEvent.acceptProposal,
        Actor.system,
      ).unwrap(),
      openedByRole: dispute.openedByRole,
      buyerClaim: dispute.buyerClaim,
      sellerClaim: dispute.sellerClaim,
      proposal: updatedProposal,
    );

    final resolved = applyEvent(
      contract.state,
      TransactionEvent.resolveDispute,
      Actor.system,
    ).unwrap();

    _replace(contract.copyWith(
      state: resolved,
      dispute: closedDispute,
      timeline: [
        ...contract.timeline,
        TimelineEntry(
          at: DateTime.now(),
          event: TransactionEvent.resolveDispute,
          actor: Actor.system,
          describe: 'Both parties accepted the proposal',
        ),
      ],
    ));
    notifyListeners();
  }

  /// Either party refusing sends the case to a human. One refusal is enough.
  void rejectProposal(String contractId) {
    final contract = contractById(contractId);
    final dispute = contract.dispute;
    if (dispute == null) return;

    final next = applyDisputeEvent(dispute.state, DisputeEvent.rejectProposal, actor);
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
              '${_viewingAs.wireName == 'buyer' ? 'The buyer' : 'The seller'} '
              'refused the proposal',
        ),
      ));
      notifyListeners();
    }
  }

  void _replace(Contract updated) {
    _contracts = [
      for (final c in _contracts) if (c.id == updated.id) updated else c,
    ];
  }

  String _describe(Contract contract, TransactionEvent event) {
    final who = contract.partyFor(_viewingAs).name;
    return switch (event) {
      TransactionEvent.submit => '$who sent the contract',
      TransactionEvent.accept => '$who accepted the terms',
      TransactionEvent.decline => '$who declined the terms',
      TransactionEvent.withdraw => '$who withdrew the contract',
      TransactionEvent.markDelivered => '$who marked the work delivered',
      TransactionEvent.requestRevision => '$who requested changes',
      TransactionEvent.confirmDelivery => '$who confirmed the delivery',
      TransactionEvent.openDispute => '$who opened a dispute',
      _ => '$who fired ${event.wireName}',
    };
  }
}
