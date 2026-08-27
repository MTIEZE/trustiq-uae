import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/demo_data.dart';
import 'data/evidence_service.dart';
import 'data/identity_provider.dart';

/// App state over a [Backend].
///
/// Every state change goes through `applyEvent` from the domain package, the
/// same table the server and the database enforce. Nothing here decides for
/// itself whether a move is legal, so the app cannot offer a button the rest
/// of the system would refuse.
///
/// Against the live backend that check is a courtesy, not a control. The
/// database re-decides every move from `auth.uid()`, and when the two answers
/// differ it is because the counterparty moved first and this screen is stale.
/// The database's answer is the one shown.
class AppState extends ChangeNotifier {
  // The lint wants an initializing formal here. Dart does not allow a private
  // named parameter, so `this._backend` is not available and this is the form
  // that compiles.
  AppState({required Backend backend, IdentityProvider? identityProvider})
      // ignore: prefer_initializing_formals
      : _backend = backend,
        _identity = identityProvider ?? const DemoIdentityProvider();

  final Backend _backend;
  final IdentityProvider _identity;
  StreamSubscription<BackendSession?>? _sessionWatch;

  List<Contract> _contracts = const [];
  bool _loading = false;
  String? _error;

  /// Which side the demo is acting as.
  ///
  /// A demo affordance, and the default side for a new contract. It earns its
  /// place because switching it shows, immediately, that the available actions
  /// belong to a role rather than to a screen. Against the live backend it
  /// decides nothing: [roleOn] reads the session against the contract, because
  /// you can be the buyer on one contract and the seller on the next.
  Role _viewingAs = Role.buyer;

  bool get isLive => _backend.isLive;
  String get backendLabel => _backend.label;
  BackendSession? get session => _backend.session;
  bool get signedIn => _backend.session != null;

  bool get loading => _loading;

  /// The last thing that went wrong, for a screen to show and dismiss.
  String? get error => _error;
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Names the provider so a screen can say what it is sending someone to.
  String get identityProviderName => _identity.displayName;

  /// False while the real UAE Pass integration is not wired up. Screens use
  /// this to be honest about what verifying does and does not prove today.
  bool get identityProviderConnected => _identity is! DemoIdentityProvider;

  /// When you were verified, or null. Read from your own profile rather than
  /// from a contract, so the answer is available before you have one.
  DateTime? get identityVerifiedAt => _backend.session?.identityVerifiedAt;

  /// Whether the app can record a verification at all, or whether it happens
  /// somewhere the app cannot reach.
  bool get canRecordVerification => _backend.canRecordVerification;

  List<Contract> get contracts => List.unmodifiable(_contracts);
  Role get viewingAs => _viewingAs;

  Contract contractById(String id) => _contracts.firstWhere((c) => c.id == id);

  /// Which side of this contract you are on.
  ///
  /// Derived from the session against the contract's parties on the live
  /// backend, so it cannot be chosen. A person who is on neither side would
  /// not have been shown the contract at all: row level security decides that
  /// before this is ever asked.
  Role roleOn(Contract contract) {
    if (!_backend.isLive) return _viewingAs;
    final me = _backend.session?.userId;
    return contract.buyer.id == me ? Role.buyer : Role.seller;
  }

  Actor actorOn(Contract contract) => Actor.ofRole(roleOn(contract));

  void viewAs(Role role) {
    if (_viewingAs == role) return;
    _setViewingAs(role);
    notifyListeners();
  }

  /// Keeps the demo backend's idea of who is acting in step with this one.
  ///
  /// A type check rather than a method on [Backend], deliberately. Choosing a
  /// side is a demo affordance and nothing else: the live backend derives the
  /// actor from the session and could not honour this if it were asked to. An
  /// interface method that one implementation is required to ignore would read
  /// as though the choice meant something everywhere.
  void _setViewingAs(Role role) {
    _viewingAs = role;
    final backend = _backend;
    if (backend is DemoBackend) backend.viewingAs = role;
  }

  /// The events this actor may fire on this contract right now.
  List<TransactionEvent> actionsFor(Contract contract) =>
      availableEventsFor(contract.state, actorOn(contract))
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
      identityGate(event, verificationFor(contract), actorOn(contract));

  /* ---------------------------------------------------------------- *
   * Session
   * ---------------------------------------------------------------- */

  /// Starts watching the session and loads whatever is already there.
  ///
  /// Called once at startup. A session is not only created by [signIn]: it is
  /// restored from storage when the app launches, refreshed in the background,
  /// and dropped when a refresh token expires. Without this, a returning
  /// person lands on their contract list and it is empty, because nothing
  /// asked for the contracts.
  Future<void> start() async {
    _sessionWatch ??= _backend.sessionChanges.listen((session) {
      if (session == null) {
        if (_contracts.isEmpty) return;
        _contracts = const [];
        notifyListeners();
        return;
      }
      // Fire and forget: this is a stream callback, and refresh reports its
      // own failures through `error`.
      unawaited(refresh());
    });

    if (_backend.session != null) await refresh();
  }

  @override
  void dispose() {
    _sessionWatch?.cancel();
    super.dispose();
  }

  Future<bool> signIn({required String email, required String password}) async {
    return _guard(() async {
      await _backend.signIn(email: email, password: password);
      _contracts = await _backend.loadContracts();
    });
  }

  /// Creates an account. Null means it failed and [error] says why.
  Future<SignUpOutcome?> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    SignUpOutcome? outcome;
    final ok = await _guard(() async {
      outcome = await _backend.signUp(email: email, password: password, fullName: fullName);
      if (outcome == SignUpOutcome.signedIn) {
        _contracts = await _backend.loadContracts();
      }
    });
    return ok ? outcome : null;
  }

  Future<bool> sendPasswordReset(String email) async {
    return _guard(() async => _backend.sendPasswordReset(email));
  }

  Future<void> signOut() async {
    await _backend.signOut();
    _contracts = const [];
    notifyListeners();
  }

  /* ---------------------------------------------------------------- *
   * Loading
   * ---------------------------------------------------------------- */

  Future<void> refresh() async {
    await _guard(() async {
      _contracts = await _backend.loadContracts();
    });
  }

  /// Runs a backend call with the loading flag and error message around it.
  ///
  /// Returns whether it succeeded. A failure is kept in [error] rather than
  /// thrown: every caller here is a button, and a button that throws leaves
  /// the person looking at a spinner with no idea what happened.
  Future<bool> _guard(Future<void> Function() body) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on BackendException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /* ---------------------------------------------------------------- *
   * Identity
   * ---------------------------------------------------------------- */

  /// Runs identity verification and records it on success.
  Future<VerificationOutcome> verifyIdentity() async {
    final outcome = await _identity.verify(role: _viewingAs);
    if (outcome is! VerificationSucceeded) return outcome;

    try {
      await _backend.recordVerification(_viewingAs);
      _contracts = await _backend.loadContracts();
      notifyListeners();
      return outcome;
    } on BackendException catch (e) {
      // The provider said yes and the record did not follow. Reporting success
      // here would show someone a verified badge that exists nowhere but their
      // screen, and the identity gate would then refuse them without a reason
      // they could see.
      return VerificationFailed(e.message);
    }
  }

  /* ---------------------------------------------------------------- *
   * Contracts
   * ---------------------------------------------------------------- */

  /// Creates a contract in draft.
  ///
  /// The amount arrives as a parsed [Fils] from the domain, so a value the
  /// domain would refuse never becomes a contract. Nothing here rounds, and
  /// nothing here holds a double.
  Future<Contract?> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterparty,
  }) async {
    Contract? created;
    final ok = await _guard(() async {
      created = await _backend.createContract(
        description: description,
        terms: terms,
        amount: amount,
        youAre: youAre,
        counterpartyEmail: counterparty,
      );
      _setViewingAs(youAre);
      _contracts = await _backend.loadContracts();
    });
    return ok ? created : null;
  }

  /// Applies an event, or returns why it was refused.
  ///
  /// The refusal path is not dead code: it is what a stale screen hits when
  /// the counterparty moved first, and the person deserves the real reason.
  Future<TransitionError?> fire(String contractId, TransactionEvent event) async {
    TransitionError? refusal;
    await _guard(() async {
      refusal = await _backend.fire(contractId, event);
      _contracts = await _backend.loadContracts();
    });
    return refusal;
  }

  /* ---------------------------------------------------------------- *
   * Disputes
   * ---------------------------------------------------------------- */

  Future<TransitionError?> openDispute(String contractId, String claim) async {
    TransitionError? refusal;
    await _guard(() async {
      refusal = await _backend.openDispute(contractId, claim);
      _contracts = await _backend.loadContracts();
    });
    return refusal;
  }

  Future<void> submitCounterClaim(String contractId, String claim) async {
    await _guard(() async {
      await _backend.submitCounterClaim(contractId, claim);
      _contracts = await _backend.loadContracts();
    });
  }

  /// Records this party accepting the current proposal.
  ///
  /// Idempotent, and the dispute closes only once both roles have accepted,
  /// exactly as `recordAcceptance` and the database define it.
  Future<void> acceptProposal(String contractId) async {
    await _guard(() async {
      await _backend.acceptProposal(contractId);
      _contracts = await _backend.loadContracts();
    });
  }

  /// Either party refusing sends the case to a human. One refusal is enough.
  Future<void> rejectProposal(String contractId) async {
    await _guard(() async {
      await _backend.rejectProposal(contractId);
      _contracts = await _backend.loadContracts();
    });
  }

  /* ---------------------------------------------------------------- *
   * Evidence
   * ---------------------------------------------------------------- */

  /// Files a document against a contract.
  ///
  /// The digest kept is the server's, computed from the bytes it stored. The
  /// app never writes a fingerprint of its own into the record: whatever it
  /// could compute locally is a claim, checked and then discarded.
  Future<EvidenceUploadResult> fileEvidence({
    required String contractId,
    required String filename,
    required String contentType,
    required Uint8List bytes,
    String? note,
  }) async {
    final contract = contractById(contractId);
    final result = await _backend.uploader.upload(
      contractId: contractId,
      uploaderRole: roleOn(contract),
      filename: filename,
      contentType: contentType,
      bytes: bytes,
      note: note,
    );

    if (result is EvidenceUploaded) {
      _contracts = await _backend.loadContracts();
      notifyListeners();
    }
    return result;
  }
}
