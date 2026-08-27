import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opening a dispute, or answering one the other party opened.
///
/// The screen exists because a contract cannot go to `disputed` without a
/// claim: the case file the model reads is built from what both sides wrote,
/// and a dispute with nothing in it is a case nobody can resolve.
class OpenDisputeScreen extends StatefulWidget {
  const OpenDisputeScreen({
    super.key,
    required this.contractId,
    required this.state,
    this.answering = false,
  });

  final String contractId;
  final AppState state;

  /// True when the other party opened the dispute and this is your reply.
  final bool answering;

  @override
  State<OpenDisputeScreen> createState() => _OpenDisputeScreenState();
}

class _OpenDisputeScreenState extends State<OpenDisputeScreen> {
  final _claim = TextEditingController();

  static const _minimumClaim = 40;

  @override
  void initState() {
    super.initState();
    _claim.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _claim.dispose();
    super.dispose();
  }

  int get _length => _claim.text.trim().length;
  bool get _canSubmit => _length >= _minimumClaim;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final contract = widget.state.contractById(widget.contractId);
    final l = context.l;
    final other = contract.counterpartyFor(widget.state.roleOn(contract));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.answering ? l.yourResponse : l.openADispute,
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(l.theContract),
                const SizedBox(height: 8),
                Text(
                  contract.description,
                  style: Type.heading,
                ),
                const SizedBox(height: Space.md),
                Text(
                  contract.terms,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(child: SectionLabel(l.amount)),
                    MoneyText(
                      contract.totalAmount,
                      style: const TextStyle(fontSize: 15),
                      emphasis: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.answering && contract.dispute != null) ...[
            const SizedBox(height: Space.md),
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(l.whatPartySays(other.name)),
                  const SizedBox(height: 8),
                  Text(
                    widget.state.roleOn(contract) == Role.buyer
                        ? (contract.dispute!.sellerClaim ?? '')
                        : contract.dispute!.buyerClaim,
                    style: Type.body,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(l.yourAccount),
                const SizedBox(height: 8),
                Text(l.claimHint, style: Type.small.copyWith(color: c.inkSoft)),
                const SizedBox(height: Space.md),
                TextField(
                  controller: _claim,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: InputDecoration(
                    hintText:
                        l.claimExample,
                    counterText: '',
                  ),
                  style: Type.body.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  _canSubmit
                      ? l.characterCount(_length)
                      : l.claimMinimum(_minimumClaim),
                  style: TextStyle(
                    fontSize: 12,
                    color: _canSubmit ? c.inkFaint : c.caution,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  widget.answering ? c.accent : c.critical,
            ),
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.answering ? l.submitYourResponse : l.openTheDispute),
          ),
          const SizedBox(height: Space.md),
          RuleNote(
            l.disputeFlowNote,
            icon: Icons.balance_outlined,
          ),
          const SizedBox(height: Space.md),
          RuleNote(
            l.claimVisibilityNote,
            icon: Icons.visibility_outlined,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final claim = _claim.text.trim();

    if (widget.answering) {
      widget.state.submitCounterClaim(widget.contractId, claim);
      Navigator.of(context).pop();
      return;
    }

    final error = await widget.state.openDispute(widget.contractId, claim);
    if (error != null && mounted) {
      // The counterparty moved first and this screen is stale. Say what the
      // domain actually said rather than a generic failure.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: context.c.critical,
        ),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }
}
