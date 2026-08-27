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
        _amountError = parsed.isPositive ? null : context.l.amountMustBePositive;
      });
    } on MoneyError {
      setState(() {
        _parsedAmount = null;
        // The domain's own message names internals; this is the same rule said
        // to the person typing.
        _amountError = raw.contains('.') && raw.split('.').last.length > 2
            ? context.l.amountTwoDecimals
            : context.l.amountFormat;
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
    final l = context.l;
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.newContract),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          // A form of three questions rather than one wall of fields. The
          // numbers are not decoration: they tell someone how much is left.
          _Step(number: 1, title: l.stepWhoWith, blurb: l.stepWhoWithBlurb),
          InfoCard(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<Role>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  segments: [
                    ButtonSegment(
                      value: Role.buyer,
                      label: Text(l.iAmPaying),
                      icon: Icon(Icons.south_west, size: IconSize.md),
                    ),
                    ButtonSegment(
                      value: Role.seller,
                      label: Text(l.iAmDelivering),
                      icon: Icon(Icons.north_east, size: IconSize.md),
                    ),
                  ],
                  selected: {_youAre},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _youAre = s.first),
                ),
                const SizedBox(height: Space.xl),
                _Field(
                  controller: _counterparty,
                  label: _youAre == Role.buyer ? l.emailOfDeliverer : l.emailOfPayer,
                  hint: 'name@example.ae',
                  keyboardType: TextInputType.emailAddress,
                  // An email, not a name. The contract is addressed to an
                  // account, and the server resolves the address to one.
                  helper: l.counterpartyHelper,
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xxl),
          _Step(number: 2, title: l.stepWhatAgreed, blurb: l.stepWhatAgreedBlurb),
          InfoCard(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  controller: _description,
                  label: l.whatIsBeingDone,
                  hint: l.exampleDescription,
                  maxLength: 120,
                ),
                const SizedBox(height: Space.xl),
                _Field(
                  controller: _terms,
                  label: l.agreedTerms,
                  hint: l.exampleTerms,
                  maxLines: 5,
                  maxLength: 1000,
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xxl),
          _Step(number: 3, title: l.stepHowMuch, blurb: l.stepHowMuchBlurb),
          InfoCard(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '500',
                    prefixText: 'AED  ',
                    prefixStyle: TextStyle(
                      color: c.inkFaint,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    errorText: _amountError,
                  ),
                  style: Type.amount.copyWith(fontSize: 22),
                ),
                if (_parsedAmount != null) ...[
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: IconSize.sm, color: c.ok),
                      const SizedBox(width: Space.sm),
                      Text(
                        l.recordedAs(formatAed(_parsedAmount!)),
                        style: Type.caption.copyWith(
                          color: c.ok,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.lg),
                RuleNote(l.noEscrowShort, icon: Icons.account_balance_outlined),
              ],
            ),
          ),

          const SizedBox(height: Space.xxl),
          FilledButton(
            onPressed: _canSubmit ? _create : null,
            child: Text(l.createAsDraft),
          ),
          const SizedBox(height: Space.md),
          RuleNote(l.draftNote, icon: Icons.edit_note_outlined),
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
          content: Text(widget.state.error ?? context.l.contractCouldNotBeCreated),
          backgroundColor: context.c.critical,
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

/// A numbered step, with a sentence saying why the step exists.
///
/// The numbers are not decoration. A form of three named steps tells someone
/// how much is left; the same fields in one column do not.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.blurb});

  final int number;
  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.md, start: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: Type.caption.copyWith(
                color: c.accentStrong,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Type.heading.copyWith(fontSize: 15.5)),
                const SizedBox(height: 3),
                Text(blurb, style: Type.small.copyWith(color: c.inkFaint)),
              ],
            ),
          ),
        ],
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
    this.keyboardType,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  /// A line under the field for a rule the person cannot otherwise know.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: Space.sm),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          autocorrect: keyboardType != TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            counterText: '',
          ),
          style: Type.body.copyWith(fontSize: 14.5),
        ),
      ],
    );
  }
}
