import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Reporting something, and refusing to deal with somebody again.
///
/// Both exist because Play's policy on user-generated content expects them and
/// two parties here exchange free text and files. Both are kept because a
/// product about trust with no way to say "this person is not acting in good
/// faith" is missing the thing it is named after.
///
/// The sheet says out loud that the other party is not told. Somebody deciding
/// whether to report a person they are mid-contract with needs to know that
/// before they press it, not after.

/// Asks why, then reports. Returns true if something was sent.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportSubject subject,
  required String subjectId,
  required Future<void> Function(ReportReason reason, String? detail) onSend,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ReportSheet(onSend: onSend),
  );
  return sent ?? false;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.onSend});

  final Future<void> Function(ReportReason reason, String? detail) onSend;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _detail = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  String _label(L l, ReportReason reason) => switch (reason) {
        ReportReason.abusive => l.reportReasonAbusive,
        ReportReason.fraud => l.reportReasonFraud,
        ReportReason.impersonation => l.reportReasonImpersonation,
        ReportReason.illegal => l.reportReasonIllegal,
        ReportReason.spam => l.reportReasonSpam,
        ReportReason.other => l.reportReasonOther,
      };

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    try {
      await widget.onSend(reason, _detail.text.trim().isEmpty ? null : _detail.text.trim());
      navigator.pop(true);
    } catch (_) {
      // The caller shows the failure. Leaving the sheet open with the reason
      // still chosen means a second attempt is one tap, not five.
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    return Padding(
      // Above the keyboard, which the detail field summons.
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.reportTitle, style: Type.title),
            const SizedBox(height: Space.sm),
            Text(l.reportLead, style: Type.small.copyWith(color: c.inkSoft)),
            const SizedBox(height: Space.lg),
            // RadioGroup rather than a groupValue on each tile: the per-tile
            // form is deprecated, and one owner of the selection is the shape
            // the framework now wants.
            RadioGroup<ReportReason>(
              groupValue: _reason,
              // RadioGroup wants a handler, not a nullable one, so the
              // in-flight case is handled inside rather than by withholding it.
              onChanged: (v) {
                if (!_sending) setState(() => _reason = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: reason,
                      title: Text(_label(l, reason)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _detail,
              enabled: !_sending,
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(hintText: l.reportDetailHint),
            ),
            const SizedBox(height: Space.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _reason == null || _sending ? null : _send,
                child: Text(l.reportSend),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
  }
}

/// Confirms refusing future contracts. Returns true if they said yes.
Future<bool> confirmBlock(BuildContext context) async {
  final l = context.l;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.blockTitle),
      content: Text(l.blockLead),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.blockConfirm),
        ),
      ],
    ),
  );
  return yes == true;
}
