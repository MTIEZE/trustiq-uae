import 'package:trustiq_core/trustiq_core.dart';

/// In-memory data so the app runs and is clickable before any backend exists.
///
/// The shapes mirror what `packages/server` will return once the Supabase
/// adapters are written, so swapping this for the real repository is a change
/// of source, not a rewrite of the screens.

class Party {
  const Party({required this.id, required this.name, required this.verified});
  final String id;
  final String name;
  final bool verified;
}

class Milestone {
  const Milestone({required this.title, required this.amount, this.deliveredAt});
  final String title;
  final Fils amount;
  final DateTime? deliveredAt;
}

class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.event,
    required this.actor,
  });
  final DateTime at;
  final TransactionEvent event;
  final Actor actor;
}

/// Whether a document's text could be read, and if not, which kind of not.
///
/// Carried all the way to the screen because the two absences are different
/// facts. A photograph has no text to read. A file that failed means there is
/// content nobody is seeing, including whoever decides the dispute, and the
/// person who filed it is the only one who can do something about that.
enum ExtractionStatus {
  notAttempted('not_attempted'),
  unsupported('unsupported'),
  failed('failed'),
  extracted('extracted'),
  truncated('truncated');

  const ExtractionStatus(this.wireName);
  final String wireName;

  bool get wasRead => this == extracted || this == truncated;
}

class EvidenceItem {
  const EvidenceItem({
    required this.id,
    required this.filename,
    required this.uploadedByRole,
    required this.uploadedAt,
    required this.sha256,
    this.note,
    this.extractionStatus = ExtractionStatus.notAttempted,
  });
  final String id;
  final String filename;
  final Role uploadedByRole;
  final DateTime uploadedAt;

  /// Computed by the server from the bytes it stored. Shown in full on the
  /// evidence sheet: it is what lets either party prove months later that a
  /// document was not swapped.
  final String sha256;
  final String? note;

  /// Set by the server at upload. The app never decides this, and never
  /// guesses it from the file extension: whether the text came out is a fact
  /// about what the server managed to read, not about the name of the file.
  final ExtractionStatus extractionStatus;
}

/// Who wrote a resolution.
///
/// Kept apart because the two are not interchangeable. A model proposal is an
/// offer both parties may refuse; a reviewer's decision is what happens when
/// one of them does. Showing them the same way would tell someone they can
/// still argue when they cannot.
enum ProposalSource {
  ai('ai'),
  human('human');

  const ProposalSource(this.wireName);
  final String wireName;
}

class ResolutionProposal {
  const ResolutionProposal({
    required this.decision,
    required this.summary,
    required this.findings,
    required this.sellerAmount,
    required this.buyerAmount,
    required this.confidence,
    required this.acceptedBy,
    this.source = ProposalSource.ai,
  });

  final ResolutionDecision decision;
  final String summary;
  final List<({String statement, List<String> evidenceIds})> findings;
  final Fils sellerAmount;
  final Fils buyerAmount;
  final ProposalSource source;

  /// Null for a human decision, and the schema insists on that: a reviewer
  /// never computed a confidence and must not appear to have one.
  final double? confidence;

  /// Roles that have accepted. The dispute closes only when both have.
  final Set<Role> acceptedBy;

  bool get bothAccepted =>
      acceptedBy.contains(Role.buyer) && acceptedBy.contains(Role.seller);
}

class Dispute {
  const Dispute({
    required this.id,
    required this.state,
    required this.openedByRole,
    required this.buyerClaim,
    this.sellerClaim,
    this.proposal,
    this.escalationReason,
  });

  final String id;
  final DisputeState state;
  final Role openedByRole;
  final String buyerClaim;
  final String? sellerClaim;
  final ResolutionProposal? proposal;
  final String? escalationReason;
}

class Contract {
  const Contract({
    required this.id,
    required this.reference,
    required this.state,
    required this.description,
    required this.terms,
    required this.totalAmount,
    required this.buyer,
    required this.seller,
    required this.createdAt,
    this.acceptanceDeadline,
    this.milestones = const [],
    this.timeline = const [],
    this.evidence = const [],
    this.dispute,
  });

  final String id;
  final String reference;
  final TransactionState state;
  final String description;
  final String terms;
  final Fils totalAmount;
  final Party buyer;
  final Party seller;
  final DateTime createdAt;
  final DateTime? acceptanceDeadline;
  final List<Milestone> milestones;
  final List<TimelineEntry> timeline;
  final List<EvidenceItem> evidence;
  final Dispute? dispute;

  Party partyFor(Role role) => role == Role.buyer ? buyer : seller;
  Party counterpartyFor(Role role) => partyFor(role.counterparty);

  /// Replaces the parties, used when someone's identity becomes verified.
  Contract withParties({required Party buyer, required Party seller}) => Contract(
        id: id,
        reference: reference,
        state: state,
        description: description,
        terms: terms,
        totalAmount: totalAmount,
        buyer: buyer,
        seller: seller,
        createdAt: createdAt,
        acceptanceDeadline: acceptanceDeadline,
        milestones: milestones,
        timeline: timeline,
        evidence: evidence,
        dispute: dispute,
      );

  /// Evidence is append-only, so this only ever grows the list.
  Contract withEvidence(List<EvidenceItem> updated) => Contract(
        id: id,
        reference: reference,
        state: state,
        description: description,
        terms: terms,
        totalAmount: totalAmount,
        buyer: buyer,
        seller: seller,
        createdAt: createdAt,
        acceptanceDeadline: acceptanceDeadline,
        milestones: milestones,
        timeline: timeline,
        evidence: updated,
        dispute: dispute,
      );

  Contract copyWith({
    TransactionState? state,
    List<TimelineEntry>? timeline,
    Dispute? dispute,
  }) {
    return Contract(
      id: id,
      reference: reference,
      state: state ?? this.state,
      description: description,
      terms: terms,
      totalAmount: totalAmount,
      buyer: buyer,
      seller: seller,
      createdAt: createdAt,
      acceptanceDeadline: acceptanceDeadline,
      milestones: milestones,
      timeline: timeline ?? this.timeline,
      evidence: evidence,
      dispute: dispute ?? this.dispute,
    );
  }
}

final _ahmed = const Party(
  id: 'usr_ahmed',
  name: 'Ahmed Al-Rashid',
  verified: true,
);
final _sara = const Party(
  id: 'usr_sara',
  name: 'Sara Design Studio',
  verified: true,
);
final _omar = const Party(id: 'usr_omar', name: 'Omar Haddad', verified: false);

DateTime _d(int day, [int hour = 9]) => DateTime(2026, 8, day, hour);

/// Seeded contracts, one per interesting state, so every screen has something
/// real to show and the action list visibly changes as the state does.
List<Contract> seedContracts() => [
      Contract(
        id: 'txn_1',
        reference: 'TIQ-2026-0847',
        state: TransactionState.disputed,
        description: 'Logo design for a startup',
        terms:
            'Deliver 3 logo concepts within 7 days. Two rounds of revision included. '
            'Final files supplied as SVG and PNG.',
        totalAmount: filsFromAed('500'),
        buyer: _ahmed,
        seller: _sara,
        createdAt: _d(1),
        milestones: [
          Milestone(title: 'Concepts', amount: filsFromAed('300'), deliveredAt: _d(8)),
          Milestone(title: 'Final files', amount: filsFromAed('200')),
        ],
        timeline: [
          TimelineEntry(
            at: _d(1),
            event: TransactionEvent.submit,
            actor: Actor.buyer,
          ),
          TimelineEntry(
            at: _d(1, 14),
            event: TransactionEvent.accept,
            actor: Actor.seller,
          ),
          TimelineEntry(
            at: _d(8),
            event: TransactionEvent.markDelivered,
            actor: Actor.seller,
          ),
          TimelineEntry(
            at: _d(10),
            event: TransactionEvent.openDispute,
            actor: Actor.buyer,
          ),
        ],
        evidence: [
          EvidenceItem(
            id: 'ev_contract',
            filename: 'signed-brief.pdf',
            // A PDF, which v1 does not read. The demo shows the real
            // behaviour rather than a flattering version of it.
            extractionStatus: ExtractionStatus.unsupported,
            uploadedByRole: Role.buyer,
            uploadedAt: _d(10, 10),
            sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            note: 'The brief we both agreed on.',
          ),
          EvidenceItem(
            id: 'ev_delivery',
            filename: 'concepts-v1.zip',
            extractionStatus: ExtractionStatus.unsupported,
            uploadedByRole: Role.seller,
            uploadedAt: _d(10, 12),
            sha256: '2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae',
            note: 'Three concepts, delivered on the 8th.',
          ),
        ],
        dispute: Dispute(
          id: 'dsp_1',
          state: DisputeState.proposalIssued,
          openedByRole: Role.buyer,
          buyerClaim:
              'Only two usable concepts were delivered and the third is a colour '
              'variation of the second. That is not what the brief asked for.',
          sellerClaim:
              'Three distinct concepts were delivered inside the agreed window. '
              'The client changed the direction after seeing them.',
          proposal: ResolutionProposal(
            decision: ResolutionDecision.split,
            summary:
                'Delivery happened inside the agreed window, which the evidence '
                'supports. Whether the third concept is genuinely distinct cannot '
                'be settled from the files alone, so the shortfall is shared rather '
                'than placed on either side.',
            findings: [
              (
                statement: 'The brief asks for three concepts within seven days.',
                evidenceIds: ['ev_contract'],
              ),
              (
                statement: 'Delivery was made on 8 August, inside that window.',
                evidenceIds: ['ev_delivery'],
              ),
            ],
            sellerAmount: filsFromAed('300'),
            buyerAmount: filsFromAed('200'),
            confidence: 0.78,
            acceptedBy: {Role.seller},
          ),
        ),
      ),
      Contract(
        id: 'txn_2',
        reference: 'TIQ-2026-0851',
        state: TransactionState.delivered,
        description: 'Arabic copywriting for a landing page',
        terms: 'Translate and adapt 900 words of marketing copy into Gulf Arabic.',
        totalAmount: filsFromAed('1200'),
        buyer: _ahmed,
        seller: _omar,
        createdAt: _d(5),
        timeline: [
          TimelineEntry(
            at: _d(5),
            event: TransactionEvent.submit,
            actor: Actor.buyer,
          ),
          TimelineEntry(
            at: _d(5, 16),
            event: TransactionEvent.accept,
            actor: Actor.seller,
          ),
          TimelineEntry(
            at: _d(12),
            event: TransactionEvent.markDelivered,
            actor: Actor.seller,
          ),
        ],
      ),
      Contract(
        id: 'txn_3',
        reference: 'TIQ-2026-0863',
        state: TransactionState.pendingAcceptance,
        description: 'Product photography, 20 items',
        terms: 'Studio shots on white, 3 angles per item, delivered as retouched JPEGs.',
        totalAmount: filsFromAed('2750'),
        buyer: _ahmed,
        seller: _sara,
        createdAt: _d(17),
        acceptanceDeadline: _d(24),
        timeline: [
          TimelineEntry(
            at: _d(17),
            event: TransactionEvent.submit,
            actor: Actor.buyer,
          ),
        ],
      ),
      Contract(
        id: 'txn_4',
        reference: 'TIQ-2026-0790',
        state: TransactionState.completed,
        description: 'Instagram content plan, one month',
        terms: 'Thirty posts with captions and a weekly posting schedule.',
        totalAmount: filsFromAed('900'),
        buyer: _ahmed,
        seller: _sara,
        createdAt: _d(2),
        timeline: [
          TimelineEntry(
            at: _d(2),
            event: TransactionEvent.submit,
            actor: Actor.buyer,
          ),
          TimelineEntry(
            at: _d(2, 11),
            event: TransactionEvent.accept,
            actor: Actor.seller,
          ),
          TimelineEntry(
            at: _d(9),
            event: TransactionEvent.markDelivered,
            actor: Actor.seller,
          ),
          TimelineEntry(
            at: _d(11),
            event: TransactionEvent.confirmDelivery,
            actor: Actor.buyer,
          ),
        ],
      ),
    ];
