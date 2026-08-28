import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'contract_detail_screen.dart';
import 'invitation_created_screen.dart';
import 'verify_identity_screen.dart';

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

  /// The stages, as fields rather than as values, because they are being
  /// typed. They become DraftStage only at the moment of submitting.
  final _stages = <({TextEditingController title, TextEditingController amount})>[];

  /// filsFromAed throws on anything it cannot read, which is right for a
  /// domain function and wrong for a field somebody is halfway through typing.
  Fils? _tryAed(String raw) {
    if (raw.isEmpty) return null;
    try {
      return filsFromAed(raw);
    } on Object {
      return null;
    }
  }

  /// What the stages add up to, or null if any of them is not a number yet.
  Fils? get _stagesTotal {
    var total = 0;
    for (final stage in _stages) {
      final parsed = _tryAed(stage.amount.text.trim());
      if (parsed == null) return null;
      total += parsed.value;
    }
    return Fils(total);
  }

  /// The stages cannot add up to more than the contract. The database refuses
  /// it too, with a deferred constraint, but finding out after the contract
  /// has been created and the stages have not is a worse way to learn.
  bool get _stagesOverTotal {
    final contract = _parsedAmount;
    final stages = _stagesTotal;
    if (contract == null || stages == null) return false;
    return stages.value > contract.value;
  }

  List<DraftStage> get _draftStages => [
        for (final stage in _stages)
          if (stage.title.text.trim().isNotEmpty)
            DraftStage(
              title: stage.title.text.trim(),
              amount: _tryAed(stage.amount.text.trim()) ?? Fils(0),
            ),
      ];

  bool get _stagesAreUsable =>
      _stages.isEmpty ||
      (!_stagesOverTotal &&
          _stages.every((s) =>
              s.title.text.trim().isNotEmpty &&
              (_tryAed(s.amount.text.trim())?.value ?? 0) > 0));

  void _addStage() {
    setState(() {
      final title = TextEditingController();
      final amount = TextEditingController();
      title.addListener(_onStageChanged);
      amount.addListener(_onStageChanged);
      _stages.add((title: title, amount: amount));
    });
  }

  void _onStageChanged() => setState(() {});

  void _removeStage(int index) {
    setState(() {
      final gone = _stages.removeAt(index);
      gone.title.dispose();
      gone.amount.dispose();
    });
  }

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
    // Created while the form is open, so the fixed list above never sees them.
    for (final stage in _stages) {
      stage.title.dispose();
      stage.amount.dispose();
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
      _parsedAmount != null &&
      // A half-typed stage is not a reason to refuse the contract, but a stage
      // with no title, no amount, or one that pushes the plan over the total,
      // is: the database would take the contract and refuse the stages, and
      // stages cannot be added afterwards.
      _stagesAreUsable;

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
          if (widget.state.isLive && widget.state.identityVerifiedAt == null) ...[
            YourIdentityNotice(state: widget.state, compact: true),
            const SizedBox(height: Space.lg),
          ],
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
                  textDirection: TextDirection.ltr,
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
                  // Left to right whatever the interface language: an amount
                  // is written the same way in both, and letting it flip would
                  // put the currency on the wrong side of the number.
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: '500',
                    prefixIcon: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.lg,
                        end: Space.sm,
                      ),
                      child: Text(
                        'AED',
                        style: Type.bodyStrong.copyWith(color: c.inkFaint, fontSize: 15),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
          const SizedBox(height: Space.section),
          _Step(number: 4, title: l.stages, blurb: l.stagesOptional),
          const SizedBox(height: Space.md),
          for (final (index, stage) in _stages.indexed) ...[
            _StageFields(
              number: index + 1,
              title: stage.title,
              amount: stage.amount,
              onRemove: () => _removeStage(index),
            ),
            const SizedBox(height: Space.sm),
          ],
          OutlinedButton.icon(
            onPressed: _stages.length >= 12 ? null : _addStage,
            icon: const Icon(Icons.add, size: IconSize.md),
            label: Text(l.addAStage),
          ),
          if (_stagesOverTotal) ...[
            const SizedBox(height: Space.sm),
            RuleNote(l.stagesOverTotal, icon: Icons.error_outline, tone: context.c.critical),
          ] else if (_stages.isNotEmpty && _parsedAmount != null && _stagesTotal != null &&
              _stagesTotal!.value < _parsedAmount!.value) ...[
            const SizedBox(height: Space.sm),
            RuleNote(
              l.stagesRemainder(formatAed(Fils(_parsedAmount!.value - _stagesTotal!.value))),
              icon: Icons.info_outline,
            ),
          ],
          if (_stages.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            RuleNote(l.stagesFixedAfter, icon: Icons.lock_outline),
          ],
          const SizedBox(height: Space.section),
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

    Contract? contract;
    try {
      contract = await widget.state.createContract(
        description: _description.text.trim(),
        terms: _terms.text.trim(),
        amount: amount,
        youAre: _youAre,
        counterparty: _counterparty.text.trim(),
        stages: _draftStages,
      );
    } on CounterpartyHasNoAccount catch (e) {
      if (!mounted) return;
      await _offerAnInvitation(e.email, amount);
      return;
    }


    if (!mounted) return;

    // Null means the backend refused. The reason is on the state, and showing
    // it here beats opening a contract screen for a contract that does not
    // exist.
    final made = contract;
    if (made == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeFailure(widget.state, context.l)?.title ??
                context.l.contractCouldNotBeCreated,
          ),
          backgroundColor: context.c.critical,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ContractDetailScreen(
          contractId: made.id,
          state: widget.state,
        ),
      ),
    );
  }

  /// The address belongs to nobody. Offer to invite them rather than stopping.
  ///
  /// Asked rather than done: an invitation puts somebody's email in TrustIQ's
  /// records and produces a code they will be sent, and neither of those
  /// should happen because a form was submitted with a typo in it.
  Future<void> _offerAnInvitation(String email, Fils amount) async {
    final l = context.l;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.noAccountTitle),
        content: Text(l.noAccountBody(email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.sendAnInvitation),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    try {
      final invitation = await widget.state.invite(
        description: _description.text.trim(),
        terms: _terms.text.trim(),
        amount: amount,
        youAre: _youAre,
        counterpartyEmail: email,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => InvitationCreatedScreen(
            invitation: invitation,
            state: widget.state,
          ),
        ),
      );
    } on BackendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: context.c.critical),
      );
    }
  }
}

/// One stage while it is being typed.
///
/// Numbered rather than labelled, because the order is what the contract will
/// record: stage one is delivered before stage two, and moving them around
/// after the contract is sent is not possible.
class _StageFields extends StatelessWidget {
  const _StageFields({
    required this.number,
    required this.title,
    required this.amount,
    required this.onRemove,
  });

  final int number;
  final TextEditingController title;
  final TextEditingController amount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    return InfoCard(
      lift: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$number',
                style: Type.caption.copyWith(color: c.inkFaint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: l.stageTitle,
                    hintText: l.stageExample,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.removeStage,
                onPressed: onRemove,
                icon: Icon(Icons.close, size: IconSize.md, color: c.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22),
            child: TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Pinned left to right: an amount is not language, and in Arabic
              // an unpinned field puts the digits back to front.
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.stageAmount),
            ),
          ),
        ],
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
    this.textDirection,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  /// A line under the field for a rule the person cannot otherwise know.
  final String? helper;

  /// Pins the field's direction. An email address and an amount are Latin in
  /// both languages, and letting them follow the interface reverses them.
  final TextDirection? textDirection;

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
          textDirection: textDirection,
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
