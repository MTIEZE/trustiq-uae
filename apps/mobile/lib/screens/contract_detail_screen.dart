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
    final c = context.c;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final contract = state.contractById(contractId);
        final l = context.l;
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
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: Center(child: StateChip(contract.state)),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
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
                              SectionLabel(l.amountAgreed),
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
                            color: c.surfaceSunken,
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(color: c.rule),
                          ),
                          child: Text(
                            state.roleOn(contract) == Role.buyer
                                ? l.youAreTheBuyer
                                : l.youAreTheSeller,
                            style: Type.caption.copyWith(color: c.inkSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xl),
                    const Divider(),
                    const SizedBox(height: Space.lg),
                    _PartyRow(label: l.you, party: me),
                    const SizedBox(height: Space.md),
                    _PartyRow(label: l.otherParty, party: other),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(l.agreedTerms),
                    const SizedBox(height: 8),
                    Text(
                      contract.terms,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (contract.milestones.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: SectionLabel(l.stages)),
                          Text(
                            l.stagesTotal(
                              contract.milestones.where((m) => m.accepted).length,
                              contract.milestones.length,
                            ),
                            style: Type.caption.copyWith(color: c.inkFaint),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final m in contract.milestones)
                        _StageRow(milestone: m, contract: contract, state: state),
                      const SizedBox(height: 4),
                      RuleNote(l.stagesNote, icon: Icons.checklist_outlined),
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
                      ? l.contractClosedNote
                      : l.nothingToDoNote(other.name),
                  icon: contract.state.isTerminal ? Icons.lock_outline : Icons.hourglass_empty,
                )
              else if (offerable.isNotEmpty) ...[
                SectionLabel(l.whatYouCanDo),
                const SizedBox(height: 10),
                for (final event in offerable) ...[
                  _ActionButton(
                    event: event,
                    onPressed: () => _fire(context, event),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                RuleNote(l.movesRuleNote, icon: Icons.rule_outlined),
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
          backgroundColor: context.c.critical,
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
    final c = context.c;
    final verified = party.verified;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            _initials,
            style: Type.caption.copyWith(
              color: c.accentStrong,
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
              Text(label, style: Type.caption.copyWith(color: c.inkFaint)),
            ],
          ),
        ),
        // Verification is the gate on this whole contract becoming active, so
        // it is stated in words rather than left to an icon somebody has to
        // interpret.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2, vertical: 4),
          decoration: BoxDecoration(
            color: verified ? c.okSoft : c.cautionSoft,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                verified ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
                size: IconSize.sm,
                color: verified ? c.ok : c.caution,
              ),
              const SizedBox(width: Space.inline),
              Text(
                verified ? context.l.verified : context.l.unverified,
                style: Type.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: verified ? c.ok : c.caution,
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
    final c = context.c;
    final dispute = contract.dispute!;
    final awaitingYou = dispute.state == DisputeState.proposalIssued &&
        dispute.proposal != null &&
        !dispute.proposal!.acceptedBy.contains(state.roleOn(contract));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: awaitingYou ? c.accent : c.rule,
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
          padding: const EdgeInsets.all(Space.xl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(context.l.dispute),
                    const SizedBox(height: 6),
                    Text(
                      disputeStateLabel(dispute.state, context.l),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (awaitingYou) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l.proposalWaitingForYou,
                        style: TextStyle(fontSize: 12.5, color: c.accent),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.inkFaint),
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
          SectionLabel(context.l.history),
          const SizedBox(height: 12),
          for (var i = 0; i < contract.timeline.length; i++)
            _TimelineRow(
              entry: contract.timeline[i],
              isLast: i == contract.timeline.length - 1,
            ),
          const SizedBox(height: 4),
          RuleNote(context.l.historyNote, icon: Icons.history_toggle_off),
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
    final c = context.c;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsetsDirectional.only(top: 5),
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: VerticalDivider(
                    color: c.rule,
                    thickness: 1,
                    width: 9,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(bottom: isLast ? 8 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeEvent(entry.event, entry.actor, context.l),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoment(entry.at, Localizations.localeOf(context)),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.inkFaint,
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

}

/// One stage, and the single move its reader is allowed to make.
///
/// The rules are in the database, and calling one of the three functions is
/// how they are enforced. What is decided here is only which button to offer:
/// showing the seller an accept button they would be refused for pressing is
/// worse than showing them nothing.
class _StageRow extends StatefulWidget {
  const _StageRow({
    required this.milestone,
    required this.contract,
    required this.state,
  });

  final Milestone milestone;
  final Contract contract;
  final AppState state;

  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  bool _busy = false;
  String? _error;

  Future<void> _move(StageMove move) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.state.moveStage(widget.milestone.id, move);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
    // No callback: the screen sits inside a ListenableBuilder on AppState and
    // moveStage notifies, so the new state arrives on its own.
  }

  Future<void> _confirmSendBack() async {
    final l = context.l;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.sendStageBackTitle),
        content: Text(l.sendStageBackBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.goBack),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.sendStageBack),
          ),
        ],
      ),
    );
    if (yes == true) await _move(StageMove.sendBack);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final m = widget.milestone;
    final youAre = widget.state.actorOn(widget.contract);
    final live = widget.contract.state == TransactionState.active ||
        widget.contract.state == TransactionState.delivered;

    final (icon, tint, label) = switch (m) {
      final s when s.accepted => (Icons.check_circle, c.ok, l.stageAccepted),
      final s when s.delivered => (Icons.pending_outlined, c.caution, l.stageDelivered),
      _ => (Icons.radio_button_unchecked, c.inkFaint, l.stageWaiting),
    };

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: IconSize.md, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: m.accepted ? c.inkSoft : c.ink,
                  ),
                ),
              ),
              Text(label, style: Type.caption.copyWith(color: tint)),
              const SizedBox(width: 10),
              MoneyText(m.amount, style: const TextStyle(fontSize: 13.5)),
            ],
          ),
          if (live && !m.accepted) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 27),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Wrap(
                      spacing: Space.sm,
                      children: [
                        if (youAre == Actor.seller && m.waiting)
                          OutlinedButton(
                            onPressed: () => _move(StageMove.deliver),
                            child: Text(l.markStageDelivered),
                          ),
                        if (youAre == Actor.buyer && m.delivered) ...[
                          FilledButton(
                            onPressed: () => _move(StageMove.accept),
                            child: Text(l.acceptStage),
                          ),
                          TextButton(
                            onPressed: _confirmSendBack,
                            child: Text(l.sendStageBack),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 27),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 13, height: 1.4, color: c.critical),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.event, required this.onPressed});
  final TransactionEvent event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = transactionEventLabel(event, context.l);
    return switch (transactionEventTone(event)) {
      ActionTone.primary => FilledButton(onPressed: onPressed, child: Text(label)),
      ActionTone.destructive => OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: c.critical,
            side: BorderSide(color: c.critical),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      ActionTone.neutral => OutlinedButton(onPressed: onPressed, child: Text(label)),
    };
  }
}
