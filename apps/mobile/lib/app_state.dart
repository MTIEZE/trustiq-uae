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
    _failure = null;
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
      _markPresent();
      // Fire and forget: this is a stream callback, and refresh reports its
      // own failures through `error`.
      unawaited(refresh());
    });

    if (_backend.session != null) {
      _markPresent();
      await refresh();
    }
  }

  bool _presentRecorded = false;

  /// Once per launch, not once per token refresh.
  ///
  /// The session stream fires whenever a token is renewed, which on a phone
  /// left open is several times a day. The insert is idempotent server side,
  /// so the extra calls would be harmless, but they would still be round trips
  /// spent saying something already said. A process is as close as this gets
  /// to "somebody opened the app", and on Android it is close enough: the
  /// system kills the process between uses far more often than it keeps it.
  void _markPresent() {
    if (_presentRecorded) return;
    _presentRecorded = true;
    // The interface says an implementation swallows its own failures, and both
    // of them do. Caught here as well because `unawaited` attaches no handler:
    // the day somebody writes a third backend that forgets, the cost should be
    // a line in the log rather than an unhandled error at launch.
    unawaited(_backend.recordActivity().catchError((Object e) {
      debugPrint('TrustIQ: could not record activity: $e');
    }));
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
      // The bell has to have a count before anybody opens the screen that
      // shows it, so activity travels with the contracts rather than waiting
      // to be asked for.
      await loadActivity();
    });
  }

  /// Runs a backend call with the loading flag and error message around it.
  ///
  /// Returns whether it succeeded. A failure is kept in [error] rather than
  /// thrown: every caller here is a button, and a button that throws leaves
  /// the person looking at a spinner with no idea what happened.
  /// Whether the last failure was the network or something we did not expect.
  ///
  /// Kept apart from [error] because these two have no words of their own:
  /// they are rendered in the reader's language by the screen, whereas a
  /// BackendException already carries a sentence.
  Failure? _failure;
  Failure? get failure => _failure;

  /// A guess, from the shape of the exception rather than its type, because
  /// the network layer under supabase_flutter throws several different ones
  /// and dart:io types are not available on every platform this builds for.
  static bool _looksLikeNetwork(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('connection refused') ||
        text.contains('timeoutexception') ||
        text.contains('network is unreachable');
  }

  Future<bool> _guard(Future<void> Function() body) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on BackendException catch (e) {
      // It came with words meant for a person, so they are used as they are.
      _error = e.message;
      _failure = null;
      return false;
    } catch (e) {
      // Never e.toString(). The exception that prompted this said
      // "Failed host lookup: 'ieccihxvmlapfuhbjuxf.supabase.co'" in a snackbar
      // on a tester's phone: unreadable to them, and it published the project
      // URL to somebody who had no reason to see it.
      _error = null;
      _failure = _looksLikeNetwork(e) ? Failure.network : Failure.unexpected;
      debugPrint('TrustIQ: unhandled backend failure: $e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /* ---------------------------------------------------------------- *
   * Identity
   * ---------------------------------------------------------------- */

  /* ---------------------------------------------------------------- *
   * Invitations
   * ---------------------------------------------------------------- */

  /// Records a contract for somebody with no account, and returns the code.
  ///
  /// Deliberately not wrapped in the shared error handling: the screen that
  /// calls this shows the code it gets back, so it has to see the failure
  /// too rather than find a banner somewhere else.
  Future<Invitation> invite({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  }) {
    return _backend.inviteCounterparty(
      description: description,
      terms: terms,
      amount: amount,
      youAre: youAre,
      counterpartyEmail: counterpartyEmail,
    );
  }

  Future<List<Invitation>> invitations() => _backend.myInvitations();

  /* ---------------------------------------------------------------- *
   * Activity
   * ---------------------------------------------------------------- */

  List<AppNotification> _activity = const [];
  List<AppNotification> get activity => _activity;

  /// How many things are waiting on you. Drives the count on the bell, and
  /// counts only what needs a move: being told the other side accepted is
  /// news, not a task, and a badge that counts news is a badge people learn
  /// to ignore.
  int get waitingOnYou => _activity.where((n) => n.unread && n.needsYou).length;

  Future<void> loadActivity() async {
    try {
      _activity = await _backend.notifications();
      notifyListeners();
    } on BackendException {
      // The bell is not worth an error banner over. The contracts underneath
      // are what matters and they loaded or did not on their own.
    }
  }

  /* ---------------------------------------------------------------- *
   * Stages
   * ---------------------------------------------------------------- */

  /// Moves one stage, then reloads. Returns null on success or the reason.
  ///
  /// The reason is returned rather than put in the banner because these three
  /// live inside a contract screen: the person is looking at the stage they
  /// just tried to move, and that is where the answer belongs.
  Future<String?> moveStage(String milestoneId, StageMove move) async {
    try {
      switch (move) {
        case StageMove.deliver:
          await _backend.deliverMilestone(milestoneId);
        case StageMove.accept:
          await _backend.acceptMilestone(milestoneId);
        case StageMove.sendBack:
          await _backend.requestMilestoneRevision(milestoneId);
      }
      _contracts = await _backend.loadContracts();
      await loadActivity();
      notifyListeners();
      return null;
    } on BackendException catch (e) {
      return e.message;
    }
  }

  /// Closes your own account. Throws with a reason if it could not.
  Future<AccountClosure> closeAccount() async {
    final result = await _backend.closeAccount();
    // Nothing left to hold. The session is already dead server-side; clearing
    // it here is what makes the app agree.
    _contracts = const [];
    _activity = const [];
    notifyListeners();
    return result;
  }

  /// Tells the server which language to write to you in.
  ///
  /// Quiet on failure. Somebody switching language should see the interface
  /// switch, not an error about a preference that will be sent again the next
  /// time they touch the control.
  Future<void> rememberLocale(String code) async {
    try {
      await _backend.setPreferredLocale(code);
    } on BackendException {
      // Not worth a banner.
    }
  }

  Future<void> markActivityRead() async {
    if (_activity.isEmpty) return;
    final newest = _activity.first.at;
    await _backend.markNotificationsRead(newest);
    await loadActivity();
  }

  Future<void> withdrawInvitation(String id) => _backend.revokeInvitation(id);

  /// Turns a code into a contract and reloads, so the caller can pop straight
  /// to a list that already has it.
  Future<String> useInvitationCode(String code) async {
    final id = await _backend.claimInvitation(code);
    _contracts = await _backend.loadContracts();
    notifyListeners();
    return id;
  }

  /// Runs identity verification and records it on success.
  /* ---------------------------------------------------------------- *
   * Where somebody stands on verification
   *
   * Held here rather than fetched by the screen, because two screens need it:
   * the one that asks, and the contract list that offers the badge. Loaded
   * lazily, because most sessions never open either.
   * ---------------------------------------------------------------- */

  MyVerification _standing = MyVerification.unknown;
  MyVerification get standing => _standing;

  bool _standingLoaded = false;

  /// Reads it once, then only when something could have changed it.
  ///
  /// Never optimistic. A failure leaves the standing at `none`, which shows
  /// somebody the button to ask rather than a badge they do not have: the
  /// wrong answer in the other direction sends them into a refusal further
  /// down, with no way to see why.
  Future<void> loadStanding({bool force = false}) async {
    if (_standingLoaded && !force) return;
    _standingLoaded = true;
    try {
      _standing = await _backend.myVerification();
    } catch (e) {
      _standing = MyVerification.unknown;
      debugPrint('TrustIQ: could not read verification standing: $e');
    }
    notifyListeners();
  }

  Future<bool> requestVerification({
    required String legalName,
    required DocumentKind documentKind,
    String? how,
  }) async {
    final ok = await _guard(() async {
      await _backend.requestVerification(
        legalName: legalName,
        documentKind: documentKind,
        how: how,
      );
    });
    // Re-read rather than assume. The server decides the state, and it is the
    // only thing that knows whether a request that appeared to succeed put
    // somebody in the queue or found them already verified.
    if (ok) await loadStanding(force: true);
    return ok;
  }

  Future<bool> withdrawVerificationRequest() async {
    final ok = await _guard(() async {
      await _backend.withdrawVerificationRequest();
    });
    if (ok) await loadStanding(force: true);
    return ok;
  }

  Future<VerificationOutcome> verifyIdentity() async {
    final outcome = await _identity.verify(role: _viewingAs);
    if (outcome is! VerificationSucceeded) return outcome;

    try {
      await _backend.recordVerification(_viewingAs);
      _contracts = await _backend.loadContracts();
      // Otherwise somebody verified through the provider keeps being shown the
      // manual queue they no longer need.
      await loadStanding(force: true);
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
    List<DraftStage> stages = const [],
  }) async {
    Contract? created;
    CounterpartyHasNoAccount? noAccount;

    final ok = await _guard(() async {
      try {
        created = await _backend.createContract(
          description: description,
          terms: terms,
          amount: amount,
          youAre: youAre,
          counterpartyEmail: counterparty,
          stages: stages,
        );
      } on CounterpartyHasNoAccount catch (e) {
        // Not a banner. This is the one failure with a way forward, and the
        // screen turns it into an offer to invite them, so it has to arrive
        // as itself rather than as a sentence in the error slot.
        noAccount = e;
        return;
      }
      _setViewingAs(youAre);
      _contracts = await _backend.loadContracts();
      await loadActivity();
    });

    if (noAccount != null) throw noAccount!;
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

/// Which of the three stage calls to make.
enum StageMove { deliver, accept, sendBack }

/// A failure with no words of its own, to be said by whoever is showing it.
enum Failure { network, unexpected }
