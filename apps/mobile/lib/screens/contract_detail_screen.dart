import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dispute_screen.dart';
import 'open_dispute_screen.dart';
import 'verify_identity_screen.dart';

class ContractDetailScreen extends StatelessWidget {
  const ContractDetailScreen({
    super.key,
    required this.contractId,
    required this.state,
  });

  final String contractId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final contract = state.contractById(contractId);
        final me = contract.partyFor(state.roleOn(contract));
        final other = contract.counterpartyFor(state.roleOn(contract));
        final actions = state.actionsFor(contract);
        // A move can be legal in the table and still blocked by a guard. The
        // database refuses these too, so the screen must not offer them as if
        // they would work.
        final blocked = {
          for (final event in actions)
            if (state.guardFor(contract, event) != null) event,
        };
        final offerable = actions.where((e) => !blocked.contains(e)).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              contract.reference,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: StateChip(contract.state)),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // The hero. What was agreed, for how much, and who with, in the
              // order somebody actually asks those questions.
              InfoCard(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contract.description, style: Type.title),
                    const SizedBox(height: Space.xl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionLabel('Amount agreed'),
                              const SizedBox(height: Space.xs),
                              MoneyText(
                                contract.totalAmount,
                                style: Type.amountLarge,
                                emphasis: true,
                              ),
                            ],
                          ),
                        ),
                        // Which side you are on, as a quiet badge rather than
                        // another labelled field. It is context, not data.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: TrustIqColors.surfaceSunken,
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(color: TrustIqColors.rule),
                          ),
                          child: Text(
                            state.roleOn(contract) == Role.buyer
                                ? 'You are the buyer'
                                : 'You are the seller',
                            style: Type.caption.copyWith(color: TrustIqColors.inkSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xl),
                    const Divider(),
                    const SizedBox(height: Space.lg),
                    _PartyRow(label: 'You', party: me),
                    const SizedBox(height: Space.md),
                    _PartyRow(label: 'Other party', party: other),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Agreed terms'),
                    const SizedBox(height: 8),
                    Text(
                      contract.terms,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (contract.milestones.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      const SectionLabel('Milestones'),
                      const SizedBox(height: 8),
                      for (final m in contract.milestones)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                m.deliveredAt != null
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 17,
                                color: m.deliveredAt != null
                                    ? TrustIqColors.ok
                                    : TrustIqColors.inkFaint,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(m.title, style: const TextStyle(fontSize: 14)),
                              ),
                              MoneyText(m.amount, style: const TextStyle(fontSize: 13.5)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (contract.dispute != null) ...[
                const SizedBox(height: 12),
                _DisputeBanner(contract: contract, state: state),
              ],
              const SizedBox(height: 12),
              _Timeline(contract: contract),
              const SizedBox(height: 20),
              if (blocked.isNotEmpty) ...[
                const SizedBox(height: 4),
                IdentityGateNotice(
                  state: state,
                  verification: state.verificationFor(contract),
                  counterpartyName: other.name,
                ),
                const SizedBox(height: 16),
              ],
              if (offerable.isEmpty && blocked.isEmpty)
                RuleNote(
                  contract.state.isTerminal
                      ? 'This contract is closed. Its record stays available to both '
                          'parties and cannot be edited by either of you.'
                      : 'Nothing for you to do right now. The next move belongs to '
                          '${other.name}.',
                  icon: contract.state.isTerminal ? Icons.lock_outline : Icons.hourglass_empty,
                )
              else if (offerable.isNotEmpty) ...[
                const SectionLabel('What you can do'),
                const SizedBox(height: 10),
                for (final event in offerable) ...[
                  _ActionButton(
                    event: event,
                    onPressed: () => _fire(context, event),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                const RuleNote(
                  'These are the only moves allowed from this state for your role. '
                  'The same rule table runs on the server and in the database, so a '
                  'move that is not offered here would be refused there too.',
                  icon: Icons.rule_outlined,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _fire(BuildContext context, TransactionEvent event) async {
    if (event == TransactionEvent.openDispute) {
      // A dispute needs the claim that opens it, so this routes to a screen
      // rather than firing the transition from a confirmation dialog.
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OpenDisputeScreen(contractId: contractId, state: state),
        ),
      );
      return;
    }
    final error = await state.fire(contractId, event);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: TrustIqColors.critical,
        ),
      );
    }
  }

}

class _PartyRow extends StatelessWidget {
  const _PartyRow({required this.label, required this.party});
  final String label;
  final Party party;

  /// Initials, so a row of people reads as people rather than as two more
  /// lines of text. Two letters at most: three starts looking like a code.
  String get _initials {
    final words = party.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final verified = party.verified;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: TrustIqColors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            _initials,
            style: Type.caption.copyWith(
              color: TrustIqColors.accentStrong,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(party.name, style: Type.bodyStrong, overflow: TextOverflow.ellipsis),
              Text(label, style: Type.caption.copyWith(color: TrustIqColors.inkFaint)),
            ],
          ),
        ),
        // Verification is the gate on this whole contract becoming active, so
        // it is stated in words rather than left to an icon somebody has to
        // interpret.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2, vertical: 4),
          decoration: BoxDecoration(
            color: verified ? TrustIqColors.okSoft : TrustIqColors.cautionSoft,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                verified ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
                size: 13,
                color: verified ? TrustIqColors.ok : TrustIqColors.caution,
              ),
              const SizedBox(width: 5),
              Text(
                verified ? 'Verified' : 'Unverified',
                style: Type.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: verified ? TrustIqColors.ok : TrustIqColors.caution,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisputeBanner extends StatelessWidget {
  const _DisputeBanner({required this.contract, required this.state});
  final Contract contract;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final dispute = contract.dispute!;
    final awaitingYou = dispute.state == DisputeState.proposalIssued &&
        dispute.proposal != null &&
        !dispute.proposal!.acceptedBy.contains(state.roleOn(contract));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: awaitingYou ? TrustIqColors.accent : TrustIqColors.rule,
          width: awaitingYou ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DisputeScreen(contractId: contract.id, state: state),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Dispute'),
                    const SizedBox(height: 6),
                    Text(
                      disputeStateLabel(dispute.state),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (awaitingYou) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'A proposal is waiting for your answer',
                        style: TextStyle(fontSize: 12.5, color: TrustIqColors.accent),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: TrustIqColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.contract});
  final Contract contract;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('History'),
          const SizedBox(height: 12),
          for (var i = 0; i < contract.timeline.length; i++)
            _TimelineRow(
              entry: contract.timeline[i],
              isLast: i == contract.timeline.length - 1,
            ),
          const SizedBox(height: 4),
          const RuleNote(
            'Every entry is written once and cannot be edited or removed, by '
            'either party or by TrustIQ.',
            icon: Icons.history_toggle_off,
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});
  final TimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  color: TrustIqColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                const Expanded(
                  child: VerticalDivider(
                    color: TrustIqColors.rule,
                    thickness: 1,
                    width: 9,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.describe,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(entry.at),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: TrustIqColors.inkFaint,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.event, required this.onPressed});
  final TransactionEvent event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = transactionEventLabel(event);
    return switch (transactionEventTone(event)) {
      ActionTone.primary => FilledButton(onPressed: onPressed, child: Text(label)),
      ActionTone.destructive => OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: TrustIqColors.critical,
            side: const BorderSide(color: TrustIqColors.critical),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      ActionTone.neutral => OutlinedButton(onPressed: onPressed, child: Text(label)),
    };
  }
}
