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

  /// One stage of work, as it is written on the form before the contract
  /// exists. Not the [Milestone] the app reads back, which has an id and a
  /// history; this is only what somebody typed.
  ///
  /// The two are kept apart on purpose. Sharing one type would mean a widget
  /// that can show a stage nobody has agreed to yet as though it had been
  /// delivered.
  ///
  /// Throws [CounterpartyHasNoAccount] when the address belongs to nobody.
  /// A typed failure rather than a message the caller has to read, because
  /// the screen turns that one case into an offer to invite them instead.
  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
    List<DraftStage> stages,
  });

  /// Records the same contract for somebody who has no account, and returns
  /// the code to send them.
  ///
  /// No contract exists yet. One appears when they claim the code, which is
  /// the first moment there are two people to hang it on.
  Future<Invitation> inviteCounterparty({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  });

  /// Turns a code into a contract. Returns its id.
  Future<String> claimInvitation(String code);

  /// What you have sent. Never what was sent to you: an invitation reaches you
  /// as a code somebody hands you, not as a list you can browse.
  Future<List<Invitation>> myInvitations();

  Future<void> revokeInvitation(String id);

  /// What has happened on your contracts since you last looked.
  Future<List<AppNotification>> notifications({int limit});

  /// Marks everything up to [before] read, so opening the list does not
  /// swallow something that landed while it was being read.
  Future<void> markNotificationsRead(DateTime before);

  /// The seller says one stage is done.
  Future<void> deliverMilestone(String milestoneId);

  /// The buyer agrees that it is.
  Future<void> acceptMilestone(String milestoneId);

  /// The buyer sends it back. The attempt stays on the record.
  Future<void> requestMilestoneRevision(String milestoneId);

  /// Closes the signed-in person's own account.
  ///
  /// Returns what happened and, when something had to be kept, what. The
  /// answer comes from the server rather than being guessed here, because
  /// only the server knows what actually points at the profile.
  Future<AccountClosure> closeAccount();

  /// Remembers which language to write to this person in.
  ///
  /// The choice lives on the device, which is right for reading the sign-in
  /// screen before there is an account and useless for writing to somebody
  /// who is not holding the phone.
  Future<void> setPreferredLocale(String code);

  /// Marks the signed-in person present today, and never complains.
  ///
  /// One row per person per day, server side, and nothing about what they did.
  /// It exists so "how many people came back" has an answer that is not a
  /// third-party tracker inside a product whose whole argument is discretion.
  ///
  /// Implementations must swallow their own failures. Nobody opening the app
  /// should ever be shown a message about a counter.
  Future<void> recordActivity();

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

/// One thing that happened on a contract you are party to.
///
/// Carries the event rather than a sentence. The database records what
/// happened; the app says it, in the language the reader chose.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.contractId,
    required this.disputeId,
    required this.aboutDispute,
    required this.event,
    required this.actor,
    required this.needsYou,
    required this.at,
    required this.readAt,
  });

  final int id;
  final String? contractId;
  final String? disputeId;

  /// Which machine the event belongs to. The two enums share names, so this
  /// is what decides how [event] is read.
  final bool aboutDispute;

  /// The wire name, as the database recorded it.
  final String event;
  final Actor actor;

  /// Whether the next move is theirs, rather than something to be told about.
  final bool needsYou;

  final DateTime at;
  final DateTime? readAt;

  bool get unread => readAt == null;
}

/// What happened when an account was closed.
class AccountClosure {
  const AccountClosure({required this.deleted, required this.kept});

  /// True when nothing pointed at the profile and it was really removed.
  final bool deleted;

  /// What had to stay, in words, or null when nothing did.
  final String? kept;
}

/// A stage as it was typed, before there is a contract to hang it on.
class DraftStage {
  const DraftStage({required this.title, required this.amount});
  final String title;
  final Fils amount;
}

/// A contract draft waiting for somebody who has not joined yet.
class Invitation {
  const Invitation({
    required this.id,
    required this.code,
    required this.email,
    required this.inviteeIs,
    required this.description,
    required this.amount,
    required this.expiresAt,
    this.claimedAt,
    this.revokedAt,
    this.contractId,
  });

  final String id;
  final String code;
  final String email;

  /// Which side the invited person is on, not which side you are.
  final Role inviteeIs;
  final String description;
  final Fils amount;
  final DateTime expiresAt;
  final DateTime? claimedAt;
  final DateTime? revokedAt;
  final String? contractId;

  bool get claimed => claimedAt != null;
  bool get revoked => revokedAt != null;
  bool get expired => !claimed && !revoked && expiresAt.isBefore(DateTime.now());

  /// Still worth sending. The three ways it stops being so are separate on
  /// purpose: the screen says which one happened rather than just going grey.
  bool get open => !claimed && !revoked && !expired;
}

/// The address on a new contract belongs to nobody yet.
///
/// Its own type because it is the one failure with a way forward: the screen
/// offers to invite them rather than telling somebody to go and recruit a
/// counterparty by themselves.
class CounterpartyHasNoAccount extends BackendException {
  CounterpartyHasNoAccount(this.email)
      : super('Nobody on TrustIQ holds $email yet.');

  final String email;
}

/// A backend call that failed for a reason worth showing someone.
class BackendException implements Exception {
  BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
