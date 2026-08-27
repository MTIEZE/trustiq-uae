import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/identity_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Verifying your identity through UAE Pass.
///
/// The screen says what will be shared and what will be kept before it sends
/// anyone anywhere. Identity verification is the point where a person hands
/// over the most, and a consent screen that hides the detail behind "continue"
/// is not consent.
class VerifyIdentityScreen extends StatefulWidget {
  const VerifyIdentityScreen({super.key, required this.state});
  final AppState state;

  @override
  State<VerifyIdentityScreen> createState() => _VerifyIdentityScreenState();
}

class _VerifyIdentityScreenState extends State<VerifyIdentityScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await widget.state.verifyIdentity();
    if (!mounted) return;

    switch (outcome) {
      case VerificationSucceeded():
        Navigator.of(context).pop(true);
      case VerificationCancelled():
        setState(() => _busy = false);
      case VerificationFailed(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;
    final connected = widget.state.identityProviderConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.verifyYourIdentity),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.bindingBetweenVerified,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: Space.md),
                Text(
                  l.canDraftWithoutVerifying,
                  style: TextStyle(fontSize: 14, height: 1.55, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(l.whatTrustIqKeeps),
                const SizedBox(height: Space.md),
                _KeptRow(
                  kept: true,
                  label: l.keepsName,
                  detail: l.keepsNameDetail,
                ),
                const SizedBox(height: Space.md),
                _KeptRow(
                  kept: true,
                  label: l.keepsReference,
                  detail: l.keepsReferenceDetail,
                ),
                const SizedBox(height: Space.md),
                _KeptRow(
                  kept: false,
                  label: l.notKeptEmiratesId,
                  detail:
                      l.notKeptEmiratesIdDetail,
                ),
                const SizedBox(height: Space.md),
                _KeptRow(
                  kept: false,
                  label: l.notKeptPersonal,
                  detail: l.notKeptPersonalDetail,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            InfoCard(
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: c.critical,
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.xxl),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: _busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onAccent),
                  )
                : Text(l.continueWith(widget.state.identityProviderName)),
          ),
          const SizedBox(height: Space.md),
          if (!connected)
            RuleNote(
              l.uaePassNotConnected,
              icon: Icons.construction_outlined,
            )
          else
            RuleNote(
              l.uaePassHandoffNote,
              icon: Icons.lock_outline,
            ),
        ],
      ),
    );
  }
}

class _KeptRow extends StatelessWidget {
  const _KeptRow({required this.kept, required this.label, required this.detail});

  final bool kept;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 2),
          child: Icon(
            kept ? Icons.check_circle_outline : Icons.block,
            size: IconSize.md,
            color: kept ? c.ok : c.inkFaint,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kept ? c.ink : c.inkSoft,
                  decoration: kept ? null : TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: c.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown where an action is blocked because someone is not verified yet.
class IdentityGateNotice extends StatelessWidget {
  const IdentityGateNotice({
    super.key,
    required this.state,
    required this.verification,
    required this.counterpartyName,
  });

  final AppState state;
  final PartyVerification verification;
  final String counterpartyName;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final youAreVerified = state.viewingAs == Role.buyer
        ? verification.buyerVerified
        : verification.sellerVerified;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.caution),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gpp_maybe_outlined, size: IconSize.md, color: c.caution),
                const SizedBox(width: 8),
                SectionLabel(context.l.cannotBeAcceptedYet),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(
              youAreVerified
                  ? '$counterpartyName has not verified their identity yet. A '
                      'contract only becomes binding between verified identities, '
                      'so nothing can be accepted until they do.'
                  : context.l.identityGateNote,
              style: const TextStyle(fontSize: 14, height: 1.55),
            ),
            if (!youAreVerified) ...[
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => VerifyIdentityScreen(state: state),
                  ),
                ),
                child: Text(context.l.verifyMyIdentity),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
