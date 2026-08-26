import 'package:trustiq_core/trustiq_core.dart';

import 'demo_data.dart';

/// Turning Postgres rows into the model the screens use.
///
/// Pure functions over plain maps, so every one of them is tested without a
/// network or a database. The queries live in `supabase_backend.dart`; nothing
/// here knows how a row was fetched.
///
/// The rule throughout: refuse rather than guess. A row that does not fit is a
/// schema change or a bug, and a mapper that quietly substitutes a default
/// turns either of those into a wrong number on someone's screen. Money is the
/// clearest case, and it is not the only one.
class RowMappingException implements Exception {
  RowMappingException(this.message);
  final String message;

  @override
  String toString() => 'RowMappingException: $message';
}

Never _fail(String message) => throw RowMappingException(message);

/// Reads a fils amount out of a row.
///
/// PostgREST sends bigint as a JSON number when it fits and as a string when
/// it does not, so both arrive here. `null` is refused outright: `int.parse`
/// on nothing is an error, but a silent zero would be a contract worth nothing.
Fils readFils(Object? value, String column) {
  final raw = switch (value) {
    int v => v,
    String v => int.tryParse(v) ?? _fail('$column is not a whole number: $v'),
    num v => v is int ? v : _fail('$column is not a whole number: $v'),
    null => _fail('$column is missing'),
    _ => _fail('$column has an unexpected type: ${value.runtimeType}'),
  };
  return Fils(raw);
}

String readString(Map<String, dynamic> row, String column) {
  final value = row[column];
  if (value is String) return value;
  _fail('$column is missing or not text');
}

DateTime readTime(Map<String, dynamic> row, String column) {
  final value = row[column];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  _fail('$column is not a timestamp: $value');
}

DateTime? readOptionalTime(Map<String, dynamic> row, String column) {
  final value = row[column];
  if (value == null) return null;
  return readTime(row, column);
}

/// Looks a wire value up in an enum, refusing anything unrecognised.
///
/// An unknown state means the database moved ahead of this build. Falling back
/// to `draft` would show a resolved contract as a draft, which is worse than a
/// visible failure.
T readEnum<T>(String value, List<T> all, String Function(T) wireName, String column) {
  for (final candidate in all) {
    if (wireName(candidate) == value) return candidate;
  }
  _fail('$column holds a value this build does not know: $value');
}

TransactionState readTransactionState(String value) =>
    readEnum(value, TransactionState.values, (s) => s.wireName, 'transactions.state');

DisputeState readDisputeState(String value) =>
    readEnum(value, DisputeState.values, (s) => s.wireName, 'disputes.state');

TransactionEvent readTransactionEvent(String value) =>
    readEnum(value, TransactionEvent.values, (e) => e.wireName, 'transaction_events.event');

Role readRole(String value, String column) =>
    readEnum(value, Role.values, (r) => r.wireName, column);

Actor readActor(String value, String column) =>
    readEnum(value, Actor.values, (a) => a.wireName, column);

ResolutionDecision readDecision(String value) => readEnum(
      value,
      ResolutionDecision.values,
      (d) => d.wireName,
      'resolution_proposals.decision',
    );

/* ------------------------------------------------------------------ *
 * Model
 * ------------------------------------------------------------------ */

Party partyFromProfile(Map<String, dynamic>? profile, String fallbackId) {
  if (profile == null) {
    // Row level security shows a party the counterparty's profile, so a null
    // here means the join found nothing rather than that access was denied.
    return Party(id: fallbackId, name: 'Unknown', verified: false);
  }
  return Party(
    id: readString(profile, 'id'),
    name: (profile['full_name'] as String?)?.trim().isNotEmpty == true
        ? profile['full_name'] as String
        : (profile['email'] as String? ?? 'Unknown'),
    // Verified means the server wrote a timestamp. The app cannot set this and
    // does not infer it from anything else on the row.
    verified: profile['identity_verified_at'] != null,
  );
}

EvidenceItem evidenceFromRow(Map<String, dynamic> row) => EvidenceItem(
      id: readString(row, 'id'),
      filename: readString(row, 'filename'),
      uploadedByRole: readRole(readString(row, 'uploaded_by_role'), 'evidence.uploaded_by_role'),
      uploadedAt: readTime(row, 'uploaded_at'),
      sha256: readString(row, 'sha256'),
      note: row['note'] as String?,
      extractionStatus: readEnum(
        (row['extraction_status'] as String?) ?? 'not_attempted',
        ExtractionStatus.values,
        (e) => e.wireName,
        'evidence.extraction_status',
      ),
    );

TimelineEntry timelineFromRow(Map<String, dynamic> row, Contract Function()? _) => TimelineEntry(
      at: readTime(row, 'occurred_at'),
      event: readTransactionEvent(readString(row, 'event')),
      actor: readActor(readString(row, 'actor'), 'transaction_events.actor'),
      describe: describeEvent(
        readTransactionEvent(readString(row, 'event')),
        readActor(readString(row, 'actor'), 'transaction_events.actor'),
      ),
    );

/// Plain words for one recorded transition.
///
/// Written from the actor rather than from a name, because the event log
/// records who acted as a role and the person reading it may be either side.
String describeEvent(TransactionEvent event, Actor actor) {
  final who = switch (actor) {
    Actor.buyer => 'The buyer',
    Actor.seller => 'The seller',
    Actor.system => 'TrustIQ',
  };
  return switch (event) {
    TransactionEvent.submit => '$who sent the contract',
    TransactionEvent.accept => '$who accepted the terms',
    TransactionEvent.decline => '$who declined the terms',
    TransactionEvent.withdraw => '$who withdrew the contract',
    TransactionEvent.markDelivered => '$who marked the work delivered',
    TransactionEvent.requestRevision => '$who requested changes',
    TransactionEvent.confirmDelivery => '$who confirmed the delivery',
    TransactionEvent.openDispute => '$who opened a dispute',
    TransactionEvent.resolveDispute => '$who resolved the dispute',
    TransactionEvent.cancelByAgreement => '$who cancelled the contract',
    TransactionEvent.expire => 'The contract expired',
  };
}

ResolutionProposal? proposalFromRows(
  Map<String, dynamic>? proposal,
  List<Map<String, dynamic>> findings,
  List<Map<String, dynamic>> citations,
  List<Map<String, dynamic>> acceptances,
) {
  if (proposal == null) return null;

  final byFinding = <String, List<String>>{};
  for (final citation in citations) {
    final findingId = readString(citation, 'finding_id');
    (byFinding[findingId] ??= []).add(readString(citation, 'evidence_id'));
  }

  final sorted = [...findings]..sort(
      (a, b) => (a['position'] as int? ?? 0).compareTo(b['position'] as int? ?? 0),
    );

  final source = readEnum(
    (proposal['source'] as String?) ?? 'ai',
    ProposalSource.values,
    (s) => s.wireName,
    'resolution_proposals.source',
  );

  return ResolutionProposal(
    source: source,
    decision: readDecision(readString(proposal, 'decision')),
    summary: readString(proposal, 'summary'),
    findings: [
      for (final finding in sorted)
        (
          statement: readString(finding, 'statement'),
          evidenceIds: byFinding[readString(finding, 'id')] ?? const <String>[],
        ),
    ],
    sellerAmount: readFils(proposal['seller_amount_fils'], 'seller_amount_fils'),
    buyerAmount: readFils(proposal['buyer_amount_fils'], 'buyer_amount_fils'),
    // Required of the model and forbidden of a human, which is exactly what
    // proposal_ai_is_attributed enforces in the schema. Reading it the same
    // way for both would either invent a confidence a reviewer never gave or
    // refuse every human decision outright.
    confidence: source == ProposalSource.human
        ? null
        : (proposal['confidence'] as num?)?.toDouble() ??
            _fail('resolution_proposals.confidence is missing on an AI proposal'),
    acceptedBy: {
      for (final acceptance in acceptances)
        readRole(readString(acceptance, 'role'), 'dispute_acceptances.role'),
    },
  );
}

Dispute? disputeFromRows(
  Map<String, dynamic>? dispute,
  ResolutionProposal? proposal,
) {
  if (dispute == null) return null;
  return Dispute(
    id: readString(dispute, 'id'),
    state: readDisputeState(readString(dispute, 'state')),
    openedByRole: readRole(readString(dispute, 'opened_by_role'), 'disputes.opened_by_role'),
    buyerClaim: dispute['buyer_claim'] as String? ?? '',
    sellerClaim: (dispute['seller_claim'] as String?)?.trim().isEmpty ?? true
        ? null
        : dispute['seller_claim'] as String,
    proposal: proposal,
  );
}

/// A short human reference, derived rather than stored.
///
/// The schema has no reference column; the id is a UUID and nobody reads one
/// aloud. This is display only and never used to look anything up.
String referenceFor(String id, DateTime createdAt) {
  final tail = id.replaceAll('-', '').substring(0, 4).toUpperCase();
  return 'TIQ-${createdAt.year}-$tail';
}
