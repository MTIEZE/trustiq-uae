import 'package:trustiq_core/trustiq_core.dart';

import 'demo_data.dart';
import 'evidence_service.dart';

/// Where contracts come from and where changes go.
///
/// Two implementations: `DemoBackend`, which keeps everything in memory so the
/// app runs with no configuration, and `SupabaseBackend`, which talks to the
/// real project. Screens and `AppState` are written against this and cannot
/// tell which one they have.
///
/// Every mutating method is a request, not an assertion. The database decides
/// whether a move is legal, using the same transition table `trustiq_core`
/// exposes to the app; the app checks first only so it can avoid offering a
/// button that would be refused. When the two disagree, the database wins and
/// the message it returns is what the person sees.
abstract interface class Backend {
  /// What this build is talking to, for showing in the interface.
  String get label;

  /// False for demo data. Screens use it to avoid claiming that anything they
  /// show has been recorded anywhere.
  bool get isLive;

  /// The signed-in person, or null when there is no session.
  BackendSession? get session;

  /// How documents are filed. Owned by the backend because the demo and the
  /// live path differ entirely.
  EvidenceUploader get uploader;

  /// Emits whenever the session appears, changes or goes away.
  ///
  /// A session is not only created by [signIn]. It is restored from storage
  /// when the app starts, refreshed in the background, and dropped when a
  /// refresh token expires. None of those go through a button, so a screen
  /// that only rebuilds after [signIn] shows a returning person an empty list
  /// and a signed-out person a stale one.
  Stream<BackendSession?> get sessionChanges;

  Future<void> signIn({required String email, required String password});

  /// Creates an account.
  ///
  /// The name is stored on the auth user rather than written straight to
  /// `profiles`, because when the project requires email confirmation there is
  /// no session yet and row level security would refuse the insert. The
  /// profile row is created on first sign-in from that stored name.
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
  });

  /// Sends a reset link. Returns whether it could have been sent.
  ///
  /// Deliberately says nothing about whether the address has an account: that
  /// answer turns a reset form into a way to enumerate a user list.
  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Every contract the signed-in person is party to.
  ///
  /// Row level security decides what that means on the live backend; nothing
  /// here filters, because a filter written twice is a filter that can
  /// disagree with itself.
  Future<List<Contract>> loadContracts();

  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  });

  /// Fires a transition. Returns null on success, or why it was refused.
  Future<TransitionError?> fire(String contractId, TransactionEvent event);

  Future<TransitionError?> openDispute(String contractId, String claim);

  Future<void> submitCounterClaim(String contractId, String claim);

  Future<void> acceptProposal(String contractId);

  Future<void> rejectProposal(String contractId);

  /// Whether this backend can record a verification from the app at all.
  ///
  /// False on the live backend, where the verification columns are
  /// server-written and no session can set them. The screen asks before it
  /// offers a button, because a button that always fails is worse than no
  /// button: it tells someone their identity is their problem to solve, and
  /// then does not let them solve it.
  bool get canRecordVerification;

  /// Marks the signed-in person's identity as verified.
  ///
  /// On the live backend this is a request the server may refuse: the schema
  /// makes the verification columns server-written, so a party cannot mark
  /// themselves verified even holding a valid session.
  Future<void> recordVerification(Role role);
}

/// What happened when an account was created.
enum SignUpOutcome {
  /// The account exists and the session is live. Straight into the app.
  signedIn,

  /// The project asks people to confirm their address first, so there is no
  /// session yet and the screen has to say so rather than appearing to hang.
  confirmationRequired,
}

/// Who is signed in.
class BackendSession {
  const BackendSession({
    required this.userId,
    required this.email,
    required this.displayName,
    this.identityVerifiedAt,
  });

  final String userId;
  final String email;
  final String displayName;

  /// When a person was verified, or null if they have not been.
  ///
  /// Carried on the session because otherwise the only way to know your own
  /// verification state is to be a party to a contract, which puts the answer
  /// behind the wall it is the reason for.
  final DateTime? identityVerifiedAt;

  bool get identityVerified => identityVerifiedAt != null;
}

/// A backend call that failed for a reason worth showing someone.
class BackendException implements Exception {
  BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
