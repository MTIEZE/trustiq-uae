import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../l10n/app_localizations.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import 'verify_identity_screen.dart';
import '../widgets/common.dart';
import 'add_evidence_screen.dart';
import 'open_dispute_screen.dart';

class DisputeScreen extends StatelessWidget {
  const DisputeScreen({super.key, required this.contractId, required this.state});

  final String contractId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final contract = state.contractById(contractId);
        final dispute = contract.dispute;
        final l = context.l;
        if (dispute == null) {
          return Scaffold(body: Center(child: Text(context.l.noDisputeOnContract)));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(l.dispute),
          ),
          body: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
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
                          SectionLabel(l.status),
                          const SizedBox(height: Space.sm),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsetsDirectional.only(end: Space.sm),
                                decoration: BoxDecoration(
                                  color: _statusColour(dispute.state, c),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  disputeStateLabel(dispute.state, context.l),
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
                        SectionLabel(l.inDispute),
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
                label: l.whatTheBuyerSays,
                who: contract.buyer.name,
                claim: dispute.buyerClaim,
                isYou: state.roleOn(contract) == Role.buyer,
              ),
              const SizedBox(height: 12),
              _ClaimCard(
                label: l.whatTheSellerSays,
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
                  icon: const Icon(Icons.add, size: IconSize.md),
                  label: Text(l.addEvidence),
                ),
              ],
              if (_awaitingYourAccount(dispute, state.roleOn(contract))) ...[
                const SizedBox(height: 12),
                InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(l.yourTurn),
                      const SizedBox(height: 8),
                      Text(
                        l.yourTurnBlurb,
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
                        child: Text(l.giveYourAccount),
                      ),
                    ],
                  ),
                ),
              ] else if (dispute.state == DisputeState.open) ...[
                const SizedBox(height: 12),
                // Waiting for the other side is a different thing from being
                // ready and needing somebody to press. The screen used to show
                // the first sentence in both cases, and there was nothing to
                // press in either: this is where the product's whole promise
                // was unreachable from the app.
                if (_bothAccountsIn(dispute))
                  _AskForResolution(contract: contract, state: state)
                else
                  RuleNote(
                    l.bothAccountsIn,
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
                      SectionLabel(l.disputeEscalated),
                      const SizedBox(height: 8),
                      Text(
                        dispute.escalationReason ??
                            l.needsAPerson,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      RuleNote(
                        l.reviewerWillRead,
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

/// True once neither side is still owed an account of what happened.
bool _bothAccountsIn(Dispute dispute) =>
    dispute.buyerClaim.trim().isNotEmpty &&
    (dispute.sellerClaim ?? '').trim().isNotEmpty;

/// Asking the model, or being told why not.
///
/// The eligibility comes from the same database function the edge function
/// consults before spending anything, so this cannot show a button the server
/// would refuse, and cannot hide one it would allow.
class _AskForResolution extends StatefulWidget {
  const _AskForResolution({required this.contract, required this.state});

  final Contract contract;
  final AppState state;

  @override
  State<_AskForResolution> createState() => _AskForResolutionState();
}

class _AskForResolutionState extends State<_AskForResolution> {
  ResolutionEligibility? _may;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final may = await widget.state.mayRequestResolution(widget.contract.id);
    if (mounted) setState(() => _may = may);
  }

  Future<void> _ask() async {
    setState(() => _running = true);
    final outcome = await widget.state.requestResolution(widget.contract.id);
    if (!mounted) return;
    setState(() => _running = false);

    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case ResolutionProposed():
      case ResolutionEscalated():
        // Both are designed endings and the screen already renders each of
        // them from the refreshed dispute, so neither needs a sentence here
        // explaining what is now visible above.
        messenger.showSnackBar(SnackBar(content: Text(context.l.resolutionStarted)));
      case ResolutionRefused():
        await _check();
      case ResolutionFailed(:final message):
        messenger.showSnackBar(SnackBar(
          content: Text(message.isEmpty ? context.l.resolutionFailed : message),
          backgroundColor: context.c.critical,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;
    final may = _may;

    if (may == null) return const SizedBox.shrink();

    if (may.block == ResolutionBlock.notVerified) {
      return InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, size: IconSize.lg, color: c.caution),
                const SizedBox(width: Space.inline),
                Expanded(
                  child: Text(l.resolutionNeedsVerified,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(l.resolutionNeedsVerifiedWhy,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VerifyIdentityScreen(state: widget.state),
                  ),
                );
                // They may have been verified while they were away, and coming
                // back to the same refusal would be its own small insult.
                if (mounted) await _check();
              },
              child: Text(l.resolutionVerifyAction),
            ),
          ],
        ),
      );
    }

    if (!may.allowed) return const SizedBox.shrink();

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(l.askResolutionTitle),
          const SizedBox(height: 8),
          Text(l.askResolutionBody,
              style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _running ? null : _ask,
            child: _running
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: c.onAccent),
                      ),
                      const SizedBox(width: Space.inline),
                      Text(l.askResolutionRunning),
                    ],
                  )
                : Text(l.askResolutionAction),
          ),
          const SizedBox(height: Space.sm),
          // Said before the press, not after. Evidence filed afterwards is
          // evidence nobody read.
          RuleNote(l.askResolutionOnce, icon: Icons.looks_one_outlined),
        ],
      ),
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
Color _statusColour(DisputeState state, TrustIqPalette c) => switch (state) {
      DisputeState.open => c.caution,
      DisputeState.aiReview => c.accent,
      DisputeState.proposalIssued => c.accent,
      DisputeState.escalated || DisputeState.humanReview => c.critical,
      DisputeState.accepted || DisputeState.resolvedByHuman => c.ok,
      DisputeState.withdrawn => c.inkFaint,
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
    final c = context.c;
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
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(Radii.sm - 2),
                  ),
                  child: Text(
                    context.l.youShort,
                    style: Type.label.copyWith(fontSize: 9.5, color: c.accentStrong),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          // The claim is the one thing on this screen a person came to read,
          // so it is set at reading size with reading leading, not at the size
          // of a caption.
          Text(
            answered ? claim! : context.l.noAccountGivenYet,
            style: answered
                ? Type.body.copyWith(fontSize: 15)
                : Type.body.copyWith(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: c.inkFaint,
                  ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(Icons.person_outline, size: IconSize.sm, color: c.inkFaint),
              const SizedBox(width: Space.inline),
              Flexible(
                child: Text(
                  who,
                  style: Type.caption.copyWith(color: c.inkFaint),
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
          SectionLabel(context.l.evidenceCount(evidence.length)),
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
          RuleNote(
            context.l.fingerprintsNote,
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
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: IconSize.md, color: c.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.filename,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'from the ${item.uploadedByRole.wireName}',
              style: TextStyle(fontSize: 11.5, color: c.inkFaint),
            ),
          ],
        ),
        if (item.note != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: Text(
              item.note!,
              style: TextStyle(fontSize: 13, height: 1.45, color: c.inkSoft),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 28),
          // A digest is only useful if two people can compare it character by
          // character, which means it has to read the same way for both of
          // them regardless of the language around it.
          child: SelectableText(
            item.sha256,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 10.5,
              color: c.inkFaint,
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
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_off_outlined, size: IconSize.sm, color: c.inkFaint),
                const SizedBox(width: Space.inline),
                Expanded(
                  child: Text(
                    unreadableNote(item.extractionStatus, context.l),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.inkFaint,
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
String unreadableNote(ExtractionStatus status, L l) => switch (status) {
      ExtractionStatus.unsupported => l.unreadableUnsupported,
      ExtractionStatus.failed => l.unreadableFailed,
      ExtractionStatus.notAttempted => l.filedBeforeExtraction,
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
    final c = context.c;
    final youAccepted = proposal.acceptedBy.contains(state.roleOn(contract));
    final otherAccepted = proposal.acceptedBy.contains(state.roleOn(contract).counterparty);
    final closed = dispute.state.isTerminal;
    final byHuman = proposal.source == ProposalSource.human;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: c.lift,
      ),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: c.accent, width: 1.5),
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
                  size: IconSize.md,
                  color: c.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SectionLabel(
                    byHuman ? context.l.decisionByReviewer : context.l.proposedResolution,
                  ),
                ),
                if (proposal.confidence != null)
                  Text(
                    context.l.confidencePercent((proposal.confidence! * 100).round()),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              decisionLabel(proposal.decision, context.l),
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
            SectionLabel(context.l.whatThisIsBasedOn),
            const SizedBox(height: 10),
            for (final finding in proposal.findings)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(top: 3),
                      child: Icon(Icons.link, size: IconSize.sm, color: c.inkFaint),
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
                            style: TextStyle(
                              fontSize: 11.5,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            RuleNote(
              context.l.groundedNote,
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
                RuleNote(
                  context.l.youHaveAccepted,
                  icon: Icons.hourglass_bottom,
                )
              else ...[
                FilledButton(
                  onPressed: () => state.acceptProposal(contract.id),
                  child: Text(context.l.acceptThisResolution),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.critical,
                    side: BorderSide(color: c.critical),
                  ),
                  onPressed: () => _confirmReject(context),
                  child: Text(context.l.refuseAndAskForHuman),
                ),
                const SizedBox(height: 12),
                RuleNote(
                  context.l.proposalNotDecisionNote,
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
        title: Text(dialogContext.l.refuseThisProposal),
        content: Text(
          dialogContext.l.refuseConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l.goBack),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.c.critical,
              minimumSize: const Size(120, 44),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              state.rejectProposal(contract.id);
            },
            child: Text(dialogContext.l.refuse),
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
    final c = context.c;
    final total = proposal.sellerAmount.value + proposal.buyerAmount.value;

    // One ordered list feeds both the bar and the legend. They used to be two
    // separate Rows that happened to list the parties in the same order; in a
    // right-to-left layout both flip, so they stayed aligned by coincidence
    // rather than by construction. Reorder one of two Rows and the colours
    // would say the opposite of the names, on a screen about somebody's money.
    final shares = [
      (
        colour: c.accent,
        label: context.l.toParty(contract.seller.name),
        amount: proposal.sellerAmount,
      ),
      (
        colour: c.caution,
        label: context.l.toParty(contract.buyer.name),
        amount: proposal.buyerAmount,
      ),
    ];

    final visible = shares.where((s) => s.amount.value > 0).toList();

    return Column(
      children: [
        SizedBox(
          height: 10,
          child: Row(
            children: [
              for (var i = 0; i < visible.length; i += 1) ...[
                // A gap, so two shares read as two shares rather than as one
                // bar that changes colour partway along.
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  flex: visible[i].amount.value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: visible[i].colour,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            for (var i = 0; i < shares.length; i += 1)
              Expanded(
                child: _AllocationLeg(
                  colour: shares[i].colour,
                  label: shares[i].label,
                  amount: shares[i].amount,
                  // The last leg hugs the far edge, whichever edge that is.
                  alignEnd: i == shares.length - 1,
                ),
              ),
          ],
        ),
        if (total != contract.totalAmount.value) ...[
          const SizedBox(height: Space.sm),
          // Should be unreachable: the pipeline rejects any allocation that
          // does not sum to the disputed amount. Shown rather than hidden,
          // because a silent mismatch on someone's money is worse than an ugly
          // warning.
          Text(
            context.l.splitDoesNotAddUp,
            style: Type.caption.copyWith(fontSize: 12, color: c.critical),
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
    final c = context.c;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
            const SizedBox(width: Space.inline),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 11.5, color: c.inkFaint),
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
    final c = context.c;
    if (closed) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: IconSize.md, color: c.ok),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l.bothPartiesAccepted,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.ok,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(context.l.whoHasAccepted),
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
    final c = context.c;
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle : Icons.radio_button_unchecked,
          size: IconSize.md,
          color: accepted ? c.ok : c.inkFaint,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13.5))),
        Text(
          accepted ? context.l.hasAccepted : context.l.notYet,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: accepted ? c.ok : c.inkFaint,
          ),
        ),
      ],
    );
  }
}
