import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/language_button.dart';
import 'verify_identity_screen.dart';

/// Who you are signed in as, and the two ways to stop being.
///
/// There was no account screen at all: signing out was an icon in a toolbar
/// and closing an account was impossible. Both belong somewhere a person would
/// think to look, next to the facts about themselves that the app holds.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _closing = false;
  AccountClosure? _closed;
  String? _error;

  Future<void> _close() async {
    final l = context.l;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.closeAccountTitle),
        content: SingleChildScrollView(child: Text(l.closeAccountBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.goBack),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.c.critical),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.closeAccountConfirm),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() {
      _closing = true;
      _error = null;
    });

    try {
      final result = await widget.state.closeAccount();
      if (!mounted) return;
      setState(() {
        _closing = false;
        _closed = result;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final session = widget.state.session;
    final closed = _closed;

    return Scaffold(
      appBar: AppBar(title: Text(l.yourAccount)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.lg, Space.md, Space.lg, Space.section),
        children: [
          if (closed != null) ...[
            // Nothing else is worth showing once the account is gone. The
            // screen becomes the receipt.
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: IconSize.lg, color: c.ok),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.accountClosed,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    closed.deleted || closed.kept == null
                        ? l.accountDeletedBody
                        : l.accountKeptBody(closed.kept!),
                    style: TextStyle(fontSize: 14.5, height: 1.6, color: c.inkSoft),
                  ),
                ],
              ),
            ),
          ] else ...[
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.signedInAs, style: Type.caption.copyWith(color: c.inkFaint)),
                  const SizedBox(height: 4),
                  Text(
                    session?.email ?? '',
                    // An address is not language and does not mirror.
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Space.md),
                  const Divider(),
                  const SizedBox(height: Space.md),
                  Text(l.language, style: Type.caption.copyWith(color: c.inkFaint)),
                  const SizedBox(height: Space.sm),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: LanguageButton(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            YourIdentityNotice(state: widget.state),
            const SizedBox(height: Space.lg),
            OutlinedButton.icon(
              onPressed: () {
                widget.state.signOut();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.logout, size: IconSize.md),
              label: Text(l.signOut),
            ),
            const SizedBox(height: Space.section),

            SectionLabel(l.closeAccount),
            const SizedBox(height: Space.sm),
            Text(
              l.closeAccountBlurb,
              style: TextStyle(fontSize: 14, height: 1.55, color: c.inkSoft),
            ),
            const SizedBox(height: Space.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: c.critical),
              ),
              const SizedBox(height: Space.sm),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _closing
                  ? const Padding(
                      padding: EdgeInsets.all(Space.sm),
                      child: SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.critical,
                        side: BorderSide(color: c.critical),
                      ),
                      onPressed: _close,
                      child: Text(l.closeAccount),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
