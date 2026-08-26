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
              InfoCard(
                child: Row(
                  children: [
                    Expanded(
                      child: LabelledValue(
                        label: 'Status',
                        child: Text(
                          disputeStateLabel(dispute.state),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    Expanded(
                      child: LabelledValue(
                        label: 'Amount in dispute',
                        child: MoneyText(
                          contract.totalAmount,
                          style: const TextStyle(fontSize: 16),
                          emphasis: true,
                        ),
                      ),
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
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SectionLabel(label),
              if (isYou) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: TrustIqColors.accentSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'YOU',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: TrustIqColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            claim ?? 'No response submitted.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontStyle: claim == null ? FontStyle.italic : FontStyle.normal,
              color: claim == null ? TrustIqColors.inkFaint : TrustIqColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            who,
            style: const TextStyle(fontSize: 12, color: TrustIqColors.inkFaint),
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
      ],
    );
  }
}

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

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TrustIqColors.accent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 17, color: TrustIqColors.accent),
                const SizedBox(width: 8),
                const Expanded(child: SectionLabel('Proposed resolution')),
                Text(
                  '${(proposal.confidence * 100).round()}% confidence',
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
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (seller > 0)
                  Expanded(flex: seller, child: Container(color: TrustIqColors.accent)),
                if (buyer > 0)
                  Expanded(flex: buyer, child: Container(color: TrustIqColors.caution)),
              ],
            ),
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
