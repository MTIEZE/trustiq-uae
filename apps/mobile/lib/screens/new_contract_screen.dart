import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'contract_detail_screen.dart';

/// Creating a contract: the product's front door.
///
/// The amount is the interesting part. It is typed as text and parsed by
/// `filsFromAed`, the same function the server and the Dart domain use, so a
/// value the domain would refuse can never become a contract. The parsed
/// result is echoed back under the field, because on a money input the person
/// should see exactly what will be recorded rather than trust that their
/// typing was interpreted the way they meant.
class NewContractScreen extends StatefulWidget {
  const NewContractScreen({super.key, required this.state});
  final AppState state;

  @override
  State<NewContractScreen> createState() => _NewContractScreenState();
}

class _NewContractScreenState extends State<NewContractScreen> {
  final _description = TextEditingController();
  final _terms = TextEditingController();
  final _amount = TextEditingController();
  final _counterparty = TextEditingController();

  Role _youAre = Role.buyer;

  /// The last successful parse, or null when the field is empty or invalid.
  Fils? _parsedAmount;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _youAre = widget.state.viewingAs;
    _amount.addListener(_reparseAmount);
    for (final c in [_description, _terms, _counterparty]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_description, _terms, _amount, _counterparty]) {
      c.dispose();
    }
    super.dispose();
  }

  void _reparseAmount() {
    final raw = _amount.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _parsedAmount = null;
        _amountError = null;
      });
      return;
    }
    try {
      final parsed = filsFromAed(raw);
      setState(() {
        _parsedAmount = parsed.isPositive ? parsed : null;
        _amountError = parsed.isPositive ? null : 'The amount must be more than zero.';
      });
    } on MoneyError {
      setState(() {
        _parsedAmount = null;
        // The domain's own message names internals; this is the same rule said
        // to the person typing.
        _amountError = raw.contains('.') && raw.split('.').last.length > 2
            ? 'Amounts go to two decimal places. 1 AED is 100 fils, and there is nothing smaller.'
            : 'Enter an amount in AED, like 500 or 1250.50.';
      });
    }
  }

  bool get _canSubmit =>
      _description.text.trim().isNotEmpty &&
      _terms.text.trim().isNotEmpty &&
      _counterparty.text.trim().isNotEmpty &&
      _parsedAmount != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'New contract',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Your side of this deal'),
                const SizedBox(height: 10),
                SegmentedButton<Role>(
                  segments: const [
                    ButtonSegment(
                      value: Role.buyer,
                      label: Text('I am paying'),
                      icon: Icon(Icons.south_west, size: 16),
                    ),
                    ButtonSegment(
                      value: Role.seller,
                      label: Text('I am delivering'),
                      icon: Icon(Icons.north_east, size: 16),
                    ),
                  ],
                  selected: {_youAre},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _youAre = s.first),
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: _counterparty,
                  label: _youAre == Role.buyer
                      ? 'Who is delivering'
                      : 'Who is paying',
                  hint: 'Their name as it appears on TrustIQ',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  controller: _description,
                  label: 'What is being done',
                  hint: 'Logo design for a startup',
                  maxLength: 120,
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: _terms,
                  label: 'Agreed terms',
                  hint:
                      'Be specific about what counts as delivered. This is what '
                      'a dispute would be judged against.',
                  maxLines: 5,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Amount'),
                const SizedBox(height: 8),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '500',
                    prefixText: 'AED  ',
                    prefixStyle: const TextStyle(
                      color: TrustIqColors.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                    errorText: _amountError,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (_parsedAmount != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.check, size: 15, color: TrustIqColors.ok),
                      const SizedBox(width: 8),
                      Text(
                        'Recorded as ${formatAed(_parsedAmount!)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: TrustIqColors.ok,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                const RuleNote(
                  'TrustIQ does not take this money. It records what you agreed '
                  'so there is something to point at later; you pay each other '
                  'directly.',
                  icon: Icons.account_balance_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSubmit ? _create : null,
            child: const Text('Create as a draft'),
          ),
          const SizedBox(height: 10),
          const RuleNote(
            'A draft is yours alone until you send it. Once the other party '
            'accepts, neither of you can change the terms.',
            icon: Icons.edit_note_outlined,
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final amount = _parsedAmount;
    if (amount == null) return;

    final contract = await widget.state.createContract(
      description: _description.text.trim(),
      terms: _terms.text.trim(),
      amount: amount,
      youAre: _youAre,
      counterparty: _counterparty.text.trim(),
    );

    if (!mounted) return;

    // Null means the backend refused. The reason is on the state, and showing
    // it here beats opening a contract screen for a contract that does not
    // exist.
    if (contract == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.state.error ?? 'The contract could not be created.'),
          backgroundColor: TrustIqColors.critical,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ContractDetailScreen(
          contractId: contract.id,
          state: widget.state,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13.5, color: TrustIqColors.inkFaint),
            border: const OutlineInputBorder(),
            counterText: '',
          ),
          style: const TextStyle(fontSize: 14.5, height: 1.4),
        ),
      ],
    );
  }
}
