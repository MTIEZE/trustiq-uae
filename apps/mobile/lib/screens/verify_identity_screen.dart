import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../l10n/app_localizations.dart';
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

  @override
  void initState() {
    super.initState();
    // The screen used to be able to answer only "verified or not". Where
    // somebody actually stands is four states, and three of them live on the
    // server, so it has to be asked.
    widget.state.loadStanding();
  }

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
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => _body(context, l, c, byHand),
      ),
    );
  }

  Widget _body(BuildContext context, L l, TrustIqPalette c, bool byHand) {
    final connected = widget.state.identityProviderConnected;
    return ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          _Status(verifiedAt: widget.state.identityVerifiedAt),
          const SizedBox(height: Space.md),
          // The explanation is for somebody deciding whether to ask. Once they
          // have asked, or been answered, it is in the way of the thing they
          // came back to read.
          if (widget.state.standing.canAsk) InfoCard(
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
            _Journey(state: widget.state)
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
    );
  }
}

/// The verification journey, in place of the dead end that was here.
///
/// What stood here was an explanation and an email address. It said who does
/// the checking and what the result is worth, all of it true, and it gave
/// somebody nothing to press. Verification is not optional in this product:
/// the database refuses to make a contract binding between unverified parties.
/// So a screen that could only explain left people at a locked door with a
/// description of the lock.
///
/// Four states now, and they were genuinely four all along; the app just could
/// not tell them apart. Never asked, waiting, refused with a reason, verified.
/// "Never asked" and "refused" looking identical was the worst of it: somebody
/// turned down had no way to learn it, and no way to fix whatever it was.
class _Journey extends StatelessWidget {
  const _Journey({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // No listener of its own: the whole body is rebuilt above whenever the
    // standing changes, and two listeners on the same notifier is one of them
    // being wrong later.
    final standing = state.standing;
    return switch (standing.standing) {
      VerificationStanding.verified => _Done(when: standing.since),
      VerificationStanding.pending => _Waiting(state: state, standing: standing),
      VerificationStanding.rejected => _Refused(state: state, standing: standing),
      VerificationStanding.needsMoreInfo => _NeedsMore(state: state, standing: standing),
      VerificationStanding.none => _AskForm(state: state),
    };
  }
}

class _Done extends StatelessWidget {
  const _Done({this.when});
  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.verifyDoneTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: Space.sm),
          Text(l.verifyDoneBody(when == null ? '' : formatDay(when!, Localizations.localeOf(context))),
              style: TextStyle(fontSize: 14, height: 1.5, color: context.c.inkSoft)),
        ],
      ),
    );
  }
}

class _Waiting extends StatefulWidget {
  const _Waiting({required this.state, required this.standing});
  final AppState state;
  final MyVerification standing;

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _busy = false;

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    final ok = await widget.state.withdrawVerificationRequest();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(context, widget.state, ok, context.l.verifyWithdrawn);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;
    final kind = widget.standing.documentKind;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hourglass_top_outlined, size: IconSize.lg, color: c.caution),
                  const SizedBox(width: Space.inline),
                  Expanded(
                    child: Text(l.verifyPendingTitle,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                l.verifyPendingBody(widget.standing.since == null
                    ? ''
                    : formatMoment(widget.standing.since!, Localizations.localeOf(context))),
                style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft),
              ),
              if (kind != null) ...[
                const SizedBox(height: Space.sm),
                Text(l.verifyPendingShowing(_documentLabel(context, kind)),
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: c.inkFaint)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        // Offered because changing your mind is not the same as being refused,
        // and somebody who asked by accident should not have to wait to be
        // told no before they can stop waiting.
        TextButton(
          onPressed: _busy ? null : _withdraw,
          child: Text(l.verifyWithdraw),
        ),
      ],
    );
  }
}

class _Refused extends StatelessWidget {
  const _Refused({required this.state, required this.standing});
  final AppState state;
  final MyVerification standing;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, size: IconSize.lg, color: c.critical),
                  const SizedBox(width: Space.inline),
                  Expanded(
                    child: Text(l.verifyRejectedTitle,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                l.verifyRejectedBody(standing.since == null
                    ? ''
                    : formatMoment(standing.since!, Localizations.localeOf(context))),
                style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft),
              ),
              // The reason is the whole point of recording a refusal instead of
              // silently doing nothing. The server will not accept one without.
              if ((standing.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.md),
                SectionLabel(l.verifyRejectedWhy),
                const SizedBox(height: 6),
                Text(standing.reason!,
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: c.ink)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        _AskForm(state: state, again: true),
      ],
    );
  }
}

/// An operator asked a question, and the request is still open.
///
/// Deliberately not the refusal card with different words. A refusal is over
/// and this is not: the person has something to do, the tone is a request
/// rather than a verdict, and the form below is the answer rather than a
/// second attempt.
class _NeedsMore extends StatelessWidget {
  const _NeedsMore({required this.state, required this.standing});

  final AppState state;
  final MyVerification standing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline, size: IconSize.lg, color: c.caution),
                  const SizedBox(width: Space.inline),
                  Expanded(
                    child: Text(l.verifyMoreTitle,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(l.verifyMoreBody,
                  style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
              // The question itself. The server will not record one without.
              if ((standing.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.md),
                SectionLabel(l.verifyMoreWhat),
                const SizedBox(height: 6),
                Text(standing.reason!,
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: c.ink)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        _AskForm(state: state, again: true),
      ],
    );
  }
}

/// Says what happened, whichever way it went.
///
/// This existed for the success case only. A request that failed left the
/// button to stop spinning and changed nothing else on the screen, which is
/// indistinguishable from a button that does nothing, and is how the first
/// person to use this concluded they had filled in a form for no reason.
void _say(BuildContext context, AppState state, bool ok, String good) {
  final messenger = ScaffoldMessenger.of(context);
  if (ok) {
    messenger.showSnackBar(SnackBar(content: Text(good)));
    return;
  }
  // Whichever the guard left behind: a sentence the server wrote for a person,
  // or a described failure when there was no sentence to show.
  final message = state.error ?? describeFailure(state, context.l)?.title;
  messenger.showSnackBar(SnackBar(
    content: Text(message ?? context.l.somethingWentWrong),
    backgroundColor: context.c.critical,
  ));
}

String _documentLabel(BuildContext context, DocumentKind kind) => switch (kind) {
      DocumentKind.emiratesId => context.l.verifyDocEmiratesId,
      DocumentKind.passport => context.l.verifyDocPassport,
      DocumentKind.tradeLicence => context.l.verifyDocTradeLicence,
    };

class _AskForm extends StatefulWidget {
  const _AskForm({required this.state, this.again = false});
  final AppState state;
  final bool again;

  @override
  State<_AskForm> createState() => _AskFormState();
}

class _AskFormState extends State<_AskForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _how = TextEditingController();
  DocumentKind _kind = DocumentKind.emiratesId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _how.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);

    final ok = await widget.state.requestVerification(
      legalName: _name.text.trim(),
      documentKind: _kind,
      how: _how.text,
    );

    if (!mounted) return;
    setState(() => _busy = false);
    _say(context, widget.state, ok, context.l.verifySent);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.c;

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.verifyStartTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 6),
          Text(l.verifyStartBody,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
          const SizedBox(height: Space.lg),

          SectionLabel(l.verifyLegalName),
          const SizedBox(height: 6),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(helperText: l.verifyLegalNameHelp, helperMaxLines: 3),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? l.verifyLegalNameMissing : null,
          ),
          const SizedBox(height: Space.lg),

          SectionLabel(l.verifyDocumentKind),
          const SizedBox(height: 8),
          // Three, because those are the three that exist here. A free text
          // field would collect thirty spellings of the same three things.
          Wrap(
            spacing: Space.inline,
            runSpacing: Space.inline,
            children: [
              for (final kind in DocumentKind.values)
                ChoiceChip(
                  label: Text(_documentLabel(context, kind)),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),

          SectionLabel(l.verifyHow),
          const SizedBox(height: 6),
          TextFormField(
            controller: _how,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(hintText: l.verifyHowHint),
          ),
          const SizedBox(height: Space.sm),

          // Said plainly, because the absence of an upload button is a
          // deliberate decision and otherwise reads as a missing feature.
          RuleNote(l.verifyNoDocumentUpload, icon: Icons.no_photography_outlined),
          const SizedBox(height: Space.lg),

          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onAccent),
                  )
                : Text(widget.again ? l.verifyAskAgain : l.verifySubmit),
          ),
        ],
      ),
    );
  }
}

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
