import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_evidence_screen.dart';
import 'open_dispute_screen.dart';

class DisputeScreen extends StatelessWidget {
  const DisputeScreen({super.key, required this.contractId, required this.state});

  final String contractId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final contract = state.contractById(contractId);
        final dispute = contract.dispute;
        if (dispute == null) {
          return const Scaffold(body: Center(child: Text('No dispute on this contract.')));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Dispute',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // The two facts that frame everything below: where the case
              // stands, and how much is riding on it.
              InfoCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel('Status'),
                          const SizedBox(height: Space.sm),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: Space.sm),
                                decoration: BoxDecoration(
                                  color: _statusColour(dispute.state),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  disputeStateLabel(dispute.state),
                                  style: Type.heading.copyWith(fontSize: 15.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.lg),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SectionLabel('In dispute'),
                        const SizedBox(height: Space.xs),
                        MoneyText(
                          contract.totalAmount,
                          style: Type.amount.copyWith(fontSize: 21),
                          emphasis: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ClaimCard(
                label: 'What the buyer says',
                who: contract.buyer.name,
                claim: dispute.buyerClaim,
                isYou: state.roleOn(contract) == Role.buyer,
              ),
              const SizedBox(height: 12),
              _ClaimCard(
                label: 'What the seller says',
                who: contract.seller.name,
                claim: dispute.sellerClaim,
                isYou: state.roleOn(contract) == Role.seller,
              ),
              const SizedBox(height: 12),
              _EvidenceCard(evidence: contract.evidence),
              if (!dispute.state.isTerminal) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddEvidenceScreen(
                        contractId: contract.id,
                        state: state,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add evidence'),
                ),
              ],
              if (_awaitingYourAccount(dispute, state.roleOn(contract))) ...[
                const SizedBox(height: 12),
                InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Your turn'),
                      const SizedBox(height: 8),
                      const Text(
                        'The other party has given their account. Nothing is '
                        'analysed until you give yours, so the case is waiting '
                        'on you.',
                        style: TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OpenDisputeScreen(
                              contractId: contract.id,
                              state: state,
                              answering: true,
                            ),
                          ),
                        ),
                        child: const Text('Give your account'),
                      ),
                    ],
                  ),
                ),
              ] else if (dispute.state == DisputeState.open) ...[
                const SizedBox(height: 12),
                const RuleNote(
                  'Both accounts are in. The case goes to the resolution agent, '
                  'which reads them against the evidence and proposes an outcome. '
                  'You will be asked to accept or refuse it.',
                  icon: Icons.schedule_outlined,
                ),
              ],
              if (dispute.proposal != null) ...[
                const SizedBox(height: 12),
                _ProposalCard(
                  contract: contract,
                  dispute: dispute,
                  proposal: dispute.proposal!,
                  state: state,
                ),
              ],
              if (dispute.state == DisputeState.escalated ||
                  dispute.state == DisputeState.humanReview) ...[
                const SizedBox(height: 12),
                InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('With a human reviewer'),
                      const SizedBox(height: 8),
                      Text(
                        dispute.escalationReason ??
                            'This case needs a person to look at it.',
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      const RuleNote(
                        'A reviewer will read the same claims and evidence you can '
                        'see here, and will contact you both before deciding.',
                        icon: Icons.support_agent_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// True when this party opened nothing and has not answered yet.
bool _awaitingYourAccount(Dispute dispute, Role you) {
  if (dispute.state != DisputeState.open) return false;
  final yours = you == Role.buyer ? dispute.buyerClaim : dispute.sellerClaim;
  return yours == null || yours.trim().isEmpty;
}

/// How far along a case is, as a colour.
///
/// Deliberately dull. A dispute is somebody's bad week, and a bright status
/// light would read as a game.
Color _statusColour(DisputeState state) => switch (state) {
      DisputeState.open => TrustIqColors.caution,
      DisputeState.aiReview => TrustIqColors.accent,
      DisputeState.proposalIssued => TrustIqColors.accent,
      DisputeState.escalated || DisputeState.humanReview => TrustIqColors.critical,
      DisputeState.accepted || DisputeState.resolvedByHuman => TrustIqColors.ok,
      DisputeState.withdrawn => TrustIqColors.inkFaint,
    };

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    required this.label,
    required this.who,
    required this.claim,
    required this.isYou,
  });

  final String label;
  final String who;
  final String? claim;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final answered = claim != null && claim!.trim().isNotEmpty;

    return InfoCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SectionLabel(label)),
              if (isYou)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: TrustIqColors.accentSoft,
                    borderRadius: BorderRadius.circular(Radii.sm - 2),
                  ),
                  child: Text(
                    'YOU',
                    style: Type.label.copyWith(fontSize: 9.5, color: TrustIqColors.accentStrong),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          // The claim is the one thing on this screen a person came to read,
          // so it is set at reading size with reading leading, not at the size
          // of a caption.
          Text(
            answered ? claim! : 'No account given yet.',
            style: answered
                ? Type.body.copyWith(fontSize: 15)
                : Type.body.copyWith(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: TrustIqColors.inkFaint,
                  ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 13, color: TrustIqColors.inkFaint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  who,
                  style: Type.caption.copyWith(color: TrustIqColors.inkFaint),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.evidence});
  final List<EvidenceItem> evidence;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Evidence (${evidence.length})'),
          const SizedBox(height: 12),
          for (var i = 0; i < evidence.length; i++) ...[
            _EvidenceRow(item: evidence[i]),
            if (i < evidence.length - 1) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 12),
          const RuleNote(
            'The fingerprint under each file is calculated by TrustIQ from the '
            'bytes it stored, not supplied by whoever uploaded it. Neither party '
            'can replace a file after filing it.',
            icon: Icons.fingerprint,
          ),
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});
  final EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined, size: 18, color: TrustIqColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.filename,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'from the ${item.uploadedByRole.wireName}',
              style: const TextStyle(fontSize: 11.5, color: TrustIqColors.inkFaint),
            ),
          ],
        ),
        if (item.note != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              item.note!,
              style: const TextStyle(fontSize: 13, height: 1.45, color: TrustIqColors.inkSoft),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: SelectableText(
            item.sha256,
            style: const TextStyle(
              fontSize: 10.5,
              color: TrustIqColors.inkFaint,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
        // Said only when it is worth saying. A document that was read needs no
        // remark; one that could not be tells the person who filed it that the
        // resolution will be decided without its contents, and they are the
        // only one who can fix that.
        if (!item.extractionStatus.wasRead) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.visibility_off_outlined, size: 13, color: TrustIqColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    unreadableNote(item.extractionStatus),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: TrustIqColors.inkFaint,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// What to tell someone about a document whose text was not read.
///
/// Three different facts, and flattening them into "unreadable" would be
/// unhelpful in the one case where the person can act. An image is expected to
/// have no text; a file that failed is a problem they can solve by filing a
/// readable version.
String unreadableNote(ExtractionStatus status) => switch (status) {
      ExtractionStatus.unsupported =>
        'The analysis cannot read this kind of file, so it will weigh the note '
            'above rather than the contents.',
      ExtractionStatus.failed =>
        'This file should have been readable and was not. If its contents '
            'matter, file them as text as well.',
      ExtractionStatus.notAttempted => 'Filed before documents were read.',
      _ => '',
    };

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.contract,
    required this.dispute,
    required this.proposal,
    required this.state,
  });

  final Contract contract;
  final Dispute dispute;
  final ResolutionProposal proposal;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final youAccepted = proposal.acceptedBy.contains(state.roleOn(contract));
    final otherAccepted = proposal.acceptedBy.contains(state.roleOn(contract).counterparty);
    final closed = dispute.state.isTerminal;
    final byHuman = proposal.source == ProposalSource.human;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: kSoftLift,
      ),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: const BorderSide(color: TrustIqColors.accent, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A model proposal and a reviewer's decision are different things
            // and are labelled differently. One is an offer either party may
            // refuse; the other is what happened because somebody did. A
            // confidence is shown only where one was actually computed.
            Row(
              children: [
                Icon(
                  byHuman ? Icons.gavel_outlined : Icons.auto_awesome_outlined,
                  size: 17,
                  color: TrustIqColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SectionLabel(
                    byHuman ? 'Decision by a TrustIQ reviewer' : 'Proposed resolution',
                  ),
                ),
                if (proposal.confidence != null)
                  Text(
                    '${(proposal.confidence! * 100).round()}% confidence',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: TrustIqColors.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              decisionLabel(proposal.decision),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _AllocationBar(proposal: proposal, contract: contract),
            const SizedBox(height: 16),
            Text(
              proposal.summary,
              style: const TextStyle(fontSize: 14, height: 1.55),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const SectionLabel('What this is based on'),
            const SizedBox(height: 10),
            for (final finding in proposal.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.link, size: 14, color: TrustIqColors.inkFaint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            finding.statement,
                            style: const TextStyle(fontSize: 13.5, height: 1.45),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            finding.evidenceIds
                                .map((id) => _filenameFor(id))
                                .join(', '),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: TrustIqColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            const RuleNote(
              'Every statement above had to cite a document that was actually '
              'filed. A finding with nothing behind it is refused before you ever '
              'see it.',
              icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 14),
            _AcceptanceState(
              youAccepted: youAccepted,
              otherAccepted: otherAccepted,
              closed: closed,
              otherName: contract.counterpartyFor(state.roleOn(contract)).name,
            ),
            if (!closed) ...[
              const SizedBox(height: 14),
              if (youAccepted)
                const RuleNote(
                  'You have accepted. Nothing takes effect until the other party '
                  'accepts as well.',
                  icon: Icons.hourglass_bottom,
                )
              else ...[
                FilledButton(
                  onPressed: () => state.acceptProposal(contract.id),
                  child: const Text('Accept this resolution'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TrustIqColors.critical,
                    side: const BorderSide(color: TrustIqColors.critical),
                  ),
                  onPressed: () => _confirmReject(context),
                  child: const Text('Refuse and ask for a human'),
                ),
                const SizedBox(height: 12),
                const RuleNote(
                  'This is a proposal, not a decision. It only takes effect if you '
                  'both accept it, and refusing sends the case to a human reviewer '
                  'at no cost to you.',
                  icon: Icons.balance_outlined,
                ),
              ],
            ],
          ],
        ),
      ),
      ),
    );
  }

  String _filenameFor(String evidenceId) {
    final match = contract.evidence.where((e) => e.id == evidenceId);
    return match.isEmpty ? evidenceId : match.first.filename;
  }

  void _confirmReject(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refuse this proposal?'),
        content: const Text(
          'The case goes to a human reviewer, who will read the same claims and '
          'evidence and contact you both.\n\n'
          'One refusal is enough: the other party does not have to agree.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Go back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TrustIqColors.critical,
              minimumSize: const Size(120, 44),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              state.rejectProposal(contract.id);
            },
            child: const Text('Refuse'),
          ),
        ],
      ),
    );
  }
}

/// The split, shown as a proportion as well as two numbers.
///
/// The bar is drawn from the fils amounts, not from a percentage the screen
/// recalculates, so what you see is what was actually allocated.
class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.proposal, required this.contract});
  final ResolutionProposal proposal;
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final seller = proposal.sellerAmount.value;
    final buyer = proposal.buyerAmount.value;
    final total = seller + buyer;

    return Column(
      children: [
        SizedBox(
          height: 10,
          child: Row(
            children: [
              if (seller > 0)
                Expanded(
                  flex: seller,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TrustIqColors.accent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              // A gap, so two shares read as two shares rather than as one bar
              // that changes colour partway along.
              if (seller > 0 && buyer > 0) const SizedBox(width: 3),
              if (buyer > 0)
                Expanded(
                  flex: buyer,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TrustIqColors.caution,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _AllocationLeg(
                colour: TrustIqColors.accent,
                label: 'To ${contract.seller.name}',
                amount: proposal.sellerAmount,
              ),
            ),
            Expanded(
              child: _AllocationLeg(
                colour: TrustIqColors.caution,
                label: 'To ${contract.buyer.name}',
                amount: proposal.buyerAmount,
                alignEnd: true,
              ),
            ),
          ],
        ),
        if (total != contract.totalAmount.value) ...[
          const SizedBox(height: 8),
          // Should be unreachable: the pipeline rejects any allocation that does
          // not sum to the disputed amount. Shown rather than hidden, because a
          // silent mismatch on someone's money is worse than an ugly warning.
          Text(
            'This split does not add up to the amount in dispute. '
            'Do not act on it; contact support.',
            style: const TextStyle(fontSize: 12, color: TrustIqColors.critical),
          ),
        ],
      ],
    );
  }
}

class _AllocationLeg extends StatelessWidget {
  const _AllocationLeg({
    required this.colour,
    required this.label,
    required this.amount,
    this.alignEnd = false,
  });

  final Color colour;
  final String label;
  final Fils amount;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: TrustIqColors.inkFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        MoneyText(amount, style: const TextStyle(fontSize: 15), emphasis: true),
      ],
    );
  }
}

class _AcceptanceState extends StatelessWidget {
  const _AcceptanceState({
    required this.youAccepted,
    required this.otherAccepted,
    required this.closed,
    required this.otherName,
  });

  final bool youAccepted;
  final bool otherAccepted;
  final bool closed;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    if (closed) {
      return Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: TrustIqColors.ok),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Both parties accepted. The dispute is closed.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: TrustIqColors.ok,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Who has accepted'),
        const SizedBox(height: 10),
        _AcceptanceRow(name: 'You', accepted: youAccepted),
        const SizedBox(height: 8),
        _AcceptanceRow(name: otherName, accepted: otherAccepted),
      ],
    );
  }
}

class _AcceptanceRow extends StatelessWidget {
  const _AcceptanceRow({required this.name, required this.accepted});
  final String name;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 17,
          color: accepted ? TrustIqColors.ok : TrustIqColors.inkFaint,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13.5))),
        Text(
          accepted ? 'Accepted' : 'Not yet',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: accepted ? TrustIqColors.ok : TrustIqColors.inkFaint,
          ),
        ),
      ],
    );
  }
}
