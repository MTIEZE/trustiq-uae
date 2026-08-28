import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/config.dart';
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

    // Live project, no UAE Pass: verification happens between a person and a
    // service-role script, nowhere this screen can reach. Offering a button
    // here would be offering a button that always fails.
    final byHand = !connected && !widget.state.canRecordVerification;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.verifyYourIdentity),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          _Status(verifiedAt: widget.state.identityVerifiedAt),
          const SizedBox(height: Space.md),
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
          if (byHand)
            const _ByHand()
          else ...[
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
        ],
      ),
    );
  }
}

/// What happens instead of a button, while UAE Pass is not connected.
///
/// It says who does the checking, what the result is worth, and that the
/// person doing it leaves a record they cannot later edit. A screen that said
/// only "coming soon" would leave someone stuck at the identity gate with no
/// idea what to do about it.
class _ByHand extends StatelessWidget {
  const _ByHand();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;
    const contact = TrustIqConfig.verificationContact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.how_to_reg_outlined, size: IconSize.lg, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.verifiedByHand,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                l.verifiedByHandBody,
                style: TextStyle(fontSize: 14, height: 1.55, color: c.inkSoft),
              ),
              const SizedBox(height: Space.md),
              Text(
                contact.isEmpty
                    ? l.verifiedByHandNoContact
                    : l.verifiedByHandContact(contact),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: contact.isEmpty ? FontWeight.w400 : FontWeight.w600,
                  color: contact.isEmpty ? c.inkSoft : c.ink,
                ),
              ),
              const SizedBox(height: Space.md),
              Text(
                l.verifiedByHandWorthLess,
                style: TextStyle(fontSize: 13.5, height: 1.55, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        RuleNote(l.verifiedByHandRecord, icon: Icons.history_edu_outlined),
        const SizedBox(height: Space.sm),
        RuleNote(l.verifiedByHandNothingToDo, icon: Icons.info_outline),
      ],
    );
  }
}

/// Where you stand, first thing.
///
/// This screen used to be reachable only from a contract that had just told
/// somebody they could not accept it, so the state was implied. It is now
/// reachable on purpose, and a screen about your identity that does not say
/// whether you have one verified is answering the wrong question.
class _Status extends StatelessWidget {
  const _Status({required this.verifiedAt});
  final DateTime? verifiedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final done = verifiedAt != null;
    final date = verifiedAt?.toLocal();

    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.verified_outlined : Icons.pending_outlined,
            size: IconSize.lg,
            color: done ? c.ok : c.caution,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.yourIdentity,
                  style: Type.caption.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: 4),
                Text(
                  done
                      ? l.identityVerifiedOn(
                          '${date!.year}-${date.month.toString().padLeft(2, '0')}'
                          '-${date.day.toString().padLeft(2, '0')}')
                      : l.identityNotVerifiedYet,
                  style: TextStyle(fontSize: 14, height: 1.5, color: c.ink),
                ),
              ],
            ),
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
/// A standing note that you cannot accept a contract yet.
///
/// The gate has always been at acceptance, and nothing ever said so until the
/// moment somebody was refused by it. That is late: you can have drafted a
/// contract, sent it, and be waiting on the other side before finding out that
/// the block is on your end. This says it where the work starts instead.
///
/// It leads with what still works. A person who can do three of the four
/// things needs to know which one is missing, not to be told they are stuck.
class YourIdentityNotice extends StatelessWidget {
  const YourIdentityNotice({super.key, required this.state, this.compact = false});

  final AppState state;

  /// For a form, where this sits beside fields rather than above a list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    // Nothing to say to somebody who is already verified. Confirming it every
    // time they open the app would be the same nag with a green tick on it.
    if (state.identityVerifiedAt != null) return const SizedBox.shrink();

    if (compact) {
      return RuleNote(l.formNeedsVerifiedNote, icon: Icons.gpp_maybe_outlined, tone: c.caution);
    }

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe_outlined, size: IconSize.lg, color: c.caution),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.youAreNotVerified,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            l.youAreNotVerifiedBody,
            style: TextStyle(fontSize: 14, height: 1.55, color: c.inkSoft),
          ),
          const SizedBox(height: Space.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VerifyIdentityScreen(state: state),
                ),
              ),
              child: Text(l.getVerified),
            ),
          ),
        ],
      ),
    );
  }
}

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
                  ? context.l.counterpartyNotVerified(counterpartyName)
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
