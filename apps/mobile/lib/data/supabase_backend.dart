import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'backend.dart';
import 'config.dart';
import 'demo_data.dart';
import 'evidence_service.dart';
import 'rows.dart';
import 'supabase_evidence_uploader.dart';

/// The real backend.
///
/// Thin on purpose. Every rule already lives in the schema: which transitions
/// are legal, who may fire them, what a party can see. This translates and
/// nothing more, and where it looks like a decision is being made here, it is
/// being read back from the database that made it.
///
/// Two things it deliberately does not do.
///
/// It does not decide the actor. `apply_transaction_event` derives buyer,
/// seller or system from `auth.uid()` against the contract and refuses to
/// accept one as an argument. The app cannot act as the counterparty even if
/// its own state is wrong, and there is no `viewingAs` here for the same
/// reason.
///
/// It does not filter. Row level security decides which contracts come back. A
/// second filter written here could disagree with the first, and the one that
/// matters is the one in the database.
class SupabaseBackend implements Backend {
  SupabaseBackend(this._client, this._config)
      : _uploader = SupabaseEvidenceUploader(_client, _config);

  final SupabaseClient _client;
  final TrustIqConfig _config;
  final SupabaseEvidenceUploader _uploader;

  @override
  String get label => _config.label;

  @override
  bool get isLive => true;

  @override
  EvidenceUploader get uploader => _uploader;

  @override
  BackendSession? get session {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return BackendSession(
      userId: user.id,
      email: user.email ?? '',
      displayName: _displayName ?? user.email ?? 'You',
      identityVerifiedAt: _verifiedAt,
    );
  }

  String? _displayName;
  DateTime? _verifiedAt;

  @override
  Stream<BackendSession?> get sessionChanges =>
      _client.auth.onAuthStateChange.asyncMap((event) async {
        // The profile has to exist before anything reads a contract, and a
        // session can arrive without anyone pressing sign in: restored from
        // storage at launch, or refreshed in the background.
        if (event.session != null) await _ensureProfile();
        return session;
      });

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw BackendException(_friendly(e));
    }
    await _ensureProfile();
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final result = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Carried on the auth user rather than written to `profiles` here:
        // with email confirmation on there is no session yet, and row level
        // security would refuse the insert. `_ensureProfile` picks it up on
        // the first sign-in.
        data: {'full_name': fullName.trim()},
      );
      if (result.session == null) return SignUpOutcome.confirmationRequired;
      await _ensureProfile();
      return SignUpOutcome.signedIn;
    } on AuthException catch (e) {
      throw BackendException(_friendly(e));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw BackendException(_friendly(e));
    }
  }

  /// Turns an auth error into something worth reading.
  ///
  /// Only where the original is actively unhelpful. Everything else is passed
  /// through as written, because inventing a friendlier message for an error
  /// nobody anticipated hides what actually happened.
  static String _friendly(AuthException e) {
    final raw = e.message.toLowerCase();
    if (raw.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Confirm your email address first. The link is in your inbox.';
    }
    if (raw.contains('already registered') || raw.contains('already been registered')) {
      return 'An account already exists for that address. Sign in instead.';
    }
    return e.message;
  }

  @override
  Future<void> signOut() async {
    _displayName = null;
    _verifiedAt = null;
    await _client.auth.signOut();
  }

  /// Makes sure a profile row exists for the signed-in user.
  ///
  /// `profiles.id` references `auth.users.id`, and every foreign key in the
  /// product points at a profile rather than at an auth user, so an account
  /// with no profile row cannot be party to anything. Creating it on first
  /// sign-in keeps that from being a silent dead end.
  Future<void> _ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final existing = await _client
        .from('profiles')
        .select('id, full_name, identity_verified_at')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      _displayName = (existing['full_name'] as String?) ?? user.email;
      _verifiedAt = DateTime.tryParse(
        (existing['identity_verified_at'] as String?) ?? '',
      );
      return;
    }

    // The name the person gave when they signed up, kept on the auth user
    // until there was a session to write it with.
    final given = (user.userMetadata?['full_name'] as String?)?.trim();
    final name = (given != null && given.isNotEmpty)
        ? given
        : user.email?.split('@').first ?? 'You';
    await _client.from('profiles').insert({
      'id': user.id,
      'email': user.email,
      'full_name': name,
    });
    _displayName = name;
    // A profile that was just created cannot be verified: only the server
    // writes that column, and it has had no chance to.
    _verifiedAt = null;
  }

  /* ---------------------------------------------------------------- *
   * Reading
   * ---------------------------------------------------------------- */

  @override
  Future<List<Contract>> loadContracts() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw BackendException('Sign in first.');

    final transactions = await _select(
      () => _client
          .from('transactions')
          .select('id, state, buyer_id, seller_id, description, terms, '
              'total_amount_fils, acceptance_deadline, created_at')
          .order('created_at', ascending: false),
      'contracts',
    );
    if (transactions.isEmpty) return const [];

    final ids = [for (final t in transactions) readString(t, 'id')];

    // Everything else in one round trip each, rather than per contract. A list
    // screen that issues four queries per row is a list screen nobody scrolls.
    final profiles = await _select(
      () => _client.from('visible_profiles').select('id, full_name, identity_verified_at'),
      'people',
    );
    final evidence = await _select(
      () => _client
          .from('evidence')
          .select('id, transaction_id, filename, uploaded_by_role, uploaded_at, sha256, note, extraction_status')
          .inFilter('transaction_id', ids)
          .order('uploaded_at'),
      'documents',
    );
    final events = await _select(
      () => _client
          .from('transaction_events')
          .select('transaction_id, event, actor, occurred_at')
          .inFilter('transaction_id', ids)
          .order('occurred_at'),
      'history',
    );
    final disputes = await _select(
      () => _client
          .from('disputes')
          .select('id, transaction_id, state, opened_by_role, buyer_claim, seller_claim')
          .inFilter('transaction_id', ids),
      'disputes',
    );

    final proposalsByDispute = <String, Map<String, dynamic>>{};
    var findings = <Map<String, dynamic>>[];
    var citations = <Map<String, dynamic>>[];
    var acceptances = <Map<String, dynamic>>[];

    if (disputes.isNotEmpty) {
      final disputeIds = [for (final d in disputes) readString(d, 'id')];
      final proposals = await _select(
        () => _client
            .from('resolution_proposals')
            .select('id, dispute_id, source, decision, summary, seller_amount_fils, '
                'buyer_amount_fils, confidence, issued_at')
            .inFilter('dispute_id', disputeIds)
            .order('issued_at'),
        'proposals',
      );
      // Append-only, ordered by issue time, so the last one wins: the current
      // proposal for a dispute is the most recent one.
      for (final p in proposals) {
        proposalsByDispute[readString(p, 'dispute_id')] = p;
      }

      if (proposalsByDispute.isNotEmpty) {
        final proposalIds = [for (final p in proposalsByDispute.values) readString(p, 'id')];
        findings = await _select(
          () => _client
              .from('resolution_findings')
              .select('id, proposal_id, position, statement')
              .inFilter('proposal_id', proposalIds),
          'findings',
        );
        acceptances = await _select(
          () => _client
              .from('dispute_acceptances')
              .select('proposal_id, role')
              .inFilter('proposal_id', proposalIds),
          'acceptances',
        );
        if (findings.isNotEmpty) {
          citations = await _select(
            () => _client
                .from('resolution_finding_evidence')
                .select('finding_id, evidence_id')
                .inFilter('finding_id', [for (final f in findings) readString(f, 'id')]),
            'citations',
          );
        }
      }
    }

    final peopleById = {for (final p in profiles) readString(p, 'id'): p};
    final disputeByTransaction = {
      for (final d in disputes) readString(d, 'transaction_id'): d,
    };

    return [
      for (final t in transactions)
        _assemble(
          transaction: t,
          peopleById: peopleById,
          evidence: evidence,
          events: events,
          dispute: disputeByTransaction[readString(t, 'id')],
          proposalsByDispute: proposalsByDispute,
          findings: findings,
          citations: citations,
          acceptances: acceptances,
        ),
    ];
  }

  Contract _assemble({
    required Map<String, dynamic> transaction,
    required Map<String, Map<String, dynamic>> peopleById,
    required List<Map<String, dynamic>> evidence,
    required List<Map<String, dynamic>> events,
    required Map<String, dynamic>? dispute,
    required Map<String, Map<String, dynamic>> proposalsByDispute,
    required List<Map<String, dynamic>> findings,
    required List<Map<String, dynamic>> citations,
    required List<Map<String, dynamic>> acceptances,
  }) {
    final id = readString(transaction, 'id');
    final createdAt = readTime(transaction, 'created_at');
    final buyerId = readString(transaction, 'buyer_id');
    final sellerId = readString(transaction, 'seller_id');

    ResolutionProposal? proposal;
    if (dispute != null) {
      final row = proposalsByDispute[readString(dispute, 'id')];
      if (row != null) {
        final proposalId = readString(row, 'id');
        final mine = [
          for (final f in findings)
            if (readString(f, 'proposal_id') == proposalId) f,
        ];
        final mineIds = {for (final f in mine) readString(f, 'id')};
        proposal = proposalFromRows(
          row,
          mine,
          [for (final c in citations) if (mineIds.contains(readString(c, 'finding_id'))) c],
          [
            for (final a in acceptances)
              if (readString(a, 'proposal_id') == proposalId) a,
          ],
        );
      }
    }

    return Contract(
      id: id,
      reference: referenceFor(id, createdAt),
      state: readTransactionState(readString(transaction, 'state')),
      description: readString(transaction, 'description'),
      terms: readString(transaction, 'terms'),
      totalAmount: readFils(transaction['total_amount_fils'], 'transactions.total_amount_fils'),
      buyer: partyFromProfile(peopleById[buyerId], buyerId),
      seller: partyFromProfile(peopleById[sellerId], sellerId),
      createdAt: createdAt,
      acceptanceDeadline: readOptionalTime(transaction, 'acceptance_deadline'),
      timeline: [
        for (final e in events)
          if (readString(e, 'transaction_id') == id) timelineFromRow(e, null),
      ],
      evidence: [
        for (final e in evidence)
          if (readString(e, 'transaction_id') == id) evidenceFromRow(e),
      ],
      dispute: disputeFromRows(dispute, proposal),
    );
  }

  /* ---------------------------------------------------------------- *
   * Writing
   * ---------------------------------------------------------------- */

  @override
  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw BackendException('Sign in first.');

    final counterpartyId = await _rpc<String?>(
      'find_counterparty',
      {'p_email': counterpartyEmail},
      'looking up $counterpartyEmail',
    );
    // Typed, because this is the one failure the screen can do something
    // about: it offers to invite them instead.
    if (counterpartyId == null) throw CounterpartyHasNoAccount(counterpartyEmail);

    late final Map<String, dynamic> created;
    try {
      created = await _client
          .from('transactions')
          .insert({
            'buyer_id': youAre == Role.buyer ? userId : counterpartyId,
            'seller_id': youAre == Role.seller ? userId : counterpartyId,
            'description': description,
            'terms': terms,
            'total_amount_fils': amount.value,
            'created_by': userId,
          })
          .select('id')
          .single();
    } on PostgrestException catch (e) {
      throw BackendException(e.message);
    }

    final contracts = await loadContracts();
    return contracts.firstWhere((c) => c.id == readString(created, 'id'));
  }

  @override
  Future<TransitionError?> fire(String contractId, TransactionEvent event) =>
      _applyTransaction(contractId, event);

  @override
  Future<TransitionError?> openDispute(String contractId, String claim) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw BackendException('Sign in first.');

    final refusal = await _applyTransaction(contractId, TransactionEvent.openDispute);
    if (refusal != null) return refusal;

    final contracts = await loadContracts();
    final contract = contracts.firstWhere((c) => c.id == contractId);
    final role = contract.buyer.id == userId ? Role.buyer : Role.seller;

    try {
      await _client.from('disputes').insert({
        'transaction_id': contractId,
        'opened_by': userId,
        'opened_by_role': role.wireName,
        'buyer_claim': role == Role.buyer ? claim : null,
        'seller_claim': role == Role.seller ? claim : null,
        // Copied from the contract as the schema requires, so a later edit to
        // the contract cannot change what was under dispute.
        'disputed_amount_fils': contract.totalAmount.value,
      });
    } on PostgrestException catch (e) {
      throw BackendException(e.message);
    }
    return null;
  }

  @override
  Future<void> submitCounterClaim(String contractId, String claim) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw BackendException('Sign in first.');

    final contracts = await loadContracts();
    final contract = contracts.firstWhere((c) => c.id == contractId);
    final dispute = contract.dispute;
    if (dispute == null) throw BackendException('This contract has no open dispute.');

    final role = contract.buyer.id == userId ? Role.buyer : Role.seller;
    try {
      // The policy only allows this while the dispute is still `open`. After
      // that the record is what the model saw, and the database enforces it.
      await _client
          .from('disputes')
          .update({role == Role.buyer ? 'buyer_claim' : 'seller_claim': claim})
          .eq('id', dispute.id);
    } on PostgrestException catch (e) {
      throw BackendException(e.message);
    }
  }

  @override
  Future<void> acceptProposal(String contractId) async {
    final proposalId = await _currentProposalId(contractId);
    try {
      await _client.rpc('accept_resolution_proposal', params: {'p_proposal_id': proposalId});
    } on PostgrestException catch (e) {
      throw BackendException(e.message);
    }
  }

  @override
  Future<void> rejectProposal(String contractId) async {
    final contracts = await loadContracts();
    final dispute = contracts.firstWhere((c) => c.id == contractId).dispute;
    if (dispute == null) throw BackendException('This contract has no dispute.');

    try {
      await _client.rpc('apply_dispute_event', params: {
        'p_dispute_id': dispute.id,
        'p_event': DisputeEvent.rejectProposal.wireName,
      });
    } on PostgrestException catch (e) {
      throw BackendException(e.message);
    }
  }

  @override
  Future<Invitation> inviteCounterparty({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
  }) async {
    final row = await _rpc<Map<String, dynamic>>(
      'invite_counterparty',
      {
        'p_email': counterpartyEmail,
        // The invitation names the side the invited person is on, which is
        // the opposite of the side the person filling the form is on.
        'p_invitee_is': youAre == Role.buyer ? 'seller' : 'buyer',
        'p_description': description,
        'p_terms': terms,
        'p_total_amount_fils': amount.value,
      },
      'inviting $counterpartyEmail',
    );
    return _invitationFrom(row);
  }

  @override
  Future<String> claimInvitation(String code) async {
    return _rpc<String>('claim_invitation', {'p_code': code}, 'using that code');
  }

  @override
  Future<List<Invitation>> myInvitations() async {
    final rows = await _rpc<List<dynamic>>('my_invitations', {}, 'your invitations');
    return rows
        .cast<Map<String, dynamic>>()
        .map(_invitationFrom)
        .toList(growable: false);
  }

  @override
  Future<void> revokeInvitation(String id) async {
    await _rpc<void>('revoke_invitation', {'p_id': id}, 'withdrawing that invitation');
  }

  Invitation _invitationFrom(Map<String, dynamic> row) => Invitation(
        id: row['id'] as String,
        code: row['code'] as String,
        email: row['invited_email'] as String,
        inviteeIs: (row['invitee_is'] as String) == 'buyer' ? Role.buyer : Role.seller,
        description: row['description'] as String,
        amount: Fils(_asInt(row['total_amount_fils'])),
        expiresAt: DateTime.parse(row['expires_at'] as String),
        claimedAt: _asDate(row['claimed_at']),
        revokedAt: _asDate(row['revoked_at']),
        contractId: row['transaction_id'] as String?,
      );

  // bigint comes back as an int from PostgREST, but a large one arrives as a
  // string. Money is never parsed loosely anywhere else in this codebase and
  // is not going to start here.
  static int _asInt(Object? v) => switch (v) {
        final int i => i,
        final String s => int.parse(s),
        _ => throw BackendException('An amount came back as $v, which is not a number.'),
      };

  static DateTime? _asDate(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  @override
  bool get canRecordVerification => false;

  @override
  Future<void> recordVerification(Role role) async {
    // Deliberately not implemented as a write. The verification columns are
    // server-written: the profiles policy re-reads the stored row on update,
    // so a party cannot mark themselves verified even holding a valid session.
    // That is the correct behaviour, and the app must not pretend otherwise.
    throw BackendException(
      'Identity verification is recorded by the server, never by the app: the '
      'database refuses a session that tries to verify itself, by design. '
      'Until UAE Pass is connected, a person at TrustIQ records it after '
      'checking your documents.',
    );
  }

  /* ---------------------------------------------------------------- *
   * Plumbing
   * ---------------------------------------------------------------- */

  Future<String> _currentProposalId(String contractId) async {
    final contracts = await loadContracts();
    final dispute = contracts.firstWhere((c) => c.id == contractId).dispute;
    if (dispute == null) throw BackendException('This contract has no dispute.');

    final rows = await _select(
      () => _client
          .from('resolution_proposals')
          .select('id, issued_at')
          .eq('dispute_id', dispute.id)
          .order('issued_at', ascending: false)
          .limit(1),
      'the current proposal',
    );
    if (rows.isEmpty) throw BackendException('There is no proposal to accept yet.');
    return readString(rows.first, 'id');
  }

  /// Fires a transition and turns a refusal into the domain's own error shape.
  ///
  /// The database is the authority here, not the local copy of the transition
  /// table. The app checks first so it can avoid offering an impossible
  /// button; when the two disagree, it is because the counterparty moved and
  /// this screen is stale, and the database's answer is the true one.
  Future<TransitionError?> _applyTransaction(String contractId, TransactionEvent event) async {
    try {
      await _client.rpc('apply_transaction_event', params: {
        'p_transaction_id': contractId,
        'p_event': event.wireName,
      });
      return null;
    } on PostgrestException catch (e) {
      // `from` and `actor` come back as what the app believed, not as fact:
      // the database refused precisely because one of them was wrong, and it
      // does not report which. The message it returns is the true account and
      // is what the person is shown.
      return TransitionError(
        code: _codeFor(e),
        message: e.message,
        from: 'unknown',
        event: event.wireName,
        actor: Actor.system,
      );
    }
  }

  /// Maps the SQLSTATE the functions raise onto the domain's own codes.
  ///
  /// `apply_dispute_event_as` raises insufficient_privilege when the actor is
  /// not allowed the move and check_violation when the move itself is not in
  /// the table. Anything else is not a transition problem and is reported as
  /// one only because the caller has nowhere else to put it.
  static TransitionErrorCode _codeFor(PostgrestException e) => switch (e.code) {
        '42501' => TransitionErrorCode.actorNotPermitted,
        _ => TransitionErrorCode.invalidTransition,
      };

  Future<List<Map<String, dynamic>>> _select(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function() query,
    String what,
  ) async {
    try {
      return await query();
    } on PostgrestException catch (e) {
      throw BackendException('Could not load $what: ${e.message}');
    }
  }

  Future<T> _rpc<T>(String name, Map<String, dynamic> params, String what) async {
    try {
      return await _client.rpc(name, params: params) as T;
    } on PostgrestException catch (e) {
      throw BackendException('$what failed: ${e.message}');
    }
  }
}
