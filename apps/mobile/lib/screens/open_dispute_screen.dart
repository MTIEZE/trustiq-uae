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
    final contract = widget.state.contractById(widget.contractId);
    final other = contract.counterpartyFor(widget.state.viewingAs);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.answering ? 'Your response' : 'Open a dispute',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('The contract'),
                const SizedBox(height: 8),
                Text(
                  contract.description,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  contract.terms,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: TrustIqColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: SectionLabel('Amount')),
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
            const SizedBox(height: 12),
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel('What ${other.name} says'),
                  const SizedBox(height: 8),
                  Text(
                    widget.state.viewingAs == Role.buyer
                        ? (contract.dispute!.sellerClaim ?? '')
                        : contract.dispute!.buyerClaim,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Your account'),
                const SizedBox(height: 8),
                const Text(
                  'Say what happened and how it differs from the terms above. '
                  'Point at dates and deliverables rather than intentions: those '
                  'are what can be checked against the evidence.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: TrustIqColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _claim,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    hintText:
                        'Only two of the three concepts were delivered, and the '
                        'third is a colour variation of the second.',
                    hintStyle: TextStyle(fontSize: 13.5, color: TrustIqColors.inkFaint),
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  style: const TextStyle(fontSize: 14.5, height: 1.5),
                ),
                const SizedBox(height: 8),
                Text(
                  _canSubmit
                      ? '$_length characters'
                      : 'At least $_minimumClaim characters. A one-line claim gives '
                          'the reviewer nothing to work with.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _canSubmit ? TrustIqColors.inkFaint : TrustIqColors.caution,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  widget.answering ? TrustIqColors.accent : TrustIqColors.critical,
            ),
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.answering ? 'Submit your response' : 'Open the dispute'),
          ),
          const SizedBox(height: 12),
          const RuleNote(
            'Both accounts and all the evidence go to the same place. An AI agent '
            'reads them and proposes a resolution, which takes effect only if you '
            'both accept it. Either of you can refuse and ask for a person.',
            icon: Icons.balance_outlined,
          ),
          const SizedBox(height: 10),
          const RuleNote(
            'What you write here is shown to the other party in full. It cannot '
            'be edited once submitted.',
            icon: Icons.visibility_outlined,
          ),
        ],
      ),
    );
  }

  void _submit() {
    final claim = _claim.text.trim();

    if (widget.answering) {
      widget.state.submitCounterClaim(widget.contractId, claim);
      Navigator.of(context).pop();
      return;
    }

    final error = widget.state.openDispute(widget.contractId, claim);
    if (error != null) {
      // The counterparty moved first and this screen is stale. Say what the
      // domain actually said rather than a generic failure.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: TrustIqColors.critical,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }
}
