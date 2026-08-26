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

  Future<void> signIn({required String email, required String password});
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

  /// Marks the signed-in person's identity as verified.
  ///
  /// On the live backend this is a request the server may refuse: the schema
  /// makes the verification columns server-written, so a party cannot mark
  /// themselves verified even holding a valid session.
  Future<void> recordVerification(Role role);
}

/// Who is signed in.
class BackendSession {
  const BackendSession({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String userId;
  final String email;
  final String displayName;
}

/// A backend call that failed for a reason worth showing someone.
class BackendException implements Exception {
  BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
