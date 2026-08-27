import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'contract_detail_screen.dart';

/// The two ends of an invitation: the codes you have sent, and the box for a
/// code somebody gave you.
///
/// One screen for both because they are the same object seen from opposite
/// sides, and somebody who was invited will often go on to invite others. Two
/// screens would mean two places to look for the same word.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final _code = TextEditingController();
  late Future<List<Invitation>> _sent;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _sent = widget.state.invitations();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _sent = widget.state.invitations());

  Future<void> _claim() async {
    setState(() => _claiming = true);
    try {
      final id = await widget.state.useInvitationCode(_code.text);
      if (!mounted) return;
      // Straight to the contract. The code was only ever a way to reach this.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ContractDetailScreen(contractId: id, state: widget.state),
        ),
      );
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: context.c.critical),
      );
    }
  }

  Future<void> _withdraw(Invitation invitation) async {
    final l = context.l;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.withdrawInvitation),
        content: Text(l.withdrawInvitationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.withdraw),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    try {
      await widget.state.withdrawInvitation(invitation.id);
      if (mounted) _reload();
    } on BackendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: context.c.critical),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.invitations)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.lg, Space.md, Space.lg, Space.section),
        children: [
          SectionLabel(l.haveACode),
          const SizedBox(height: Space.sm),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _code,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  // Pinned left to right: a code is not language, and in
                  // Arabic an unpinned field would run the other way and read
                  // back wrong to somebody checking it against a message.
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: l.enterTheCode,
                    hintText: l.codeHint,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _code.text.trim().length < 8 || _claiming ? null : _claim,
                    child: Text(l.useTheCode),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          RuleNote(l.codeNote, icon: Icons.lock_outline),
          const SizedBox(height: Space.section),

          SectionLabel(l.invitationsSent),
          const SizedBox(height: Space.sm),
          FutureBuilder<List<Invitation>>(
            future: _sent,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return InfoCard(
                  child: Text(
                    '${snapshot.error}',
                    style: TextStyle(fontSize: 14, height: 1.5, color: context.c.critical),
                  ),
                );
              }
              final sent = snapshot.data ?? const <Invitation>[];
              if (sent.isEmpty) {
                return InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.noInvitationsYet,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.noInvitationsYetBody,
                        style: TextStyle(fontSize: 14, height: 1.5, color: context.c.inkSoft),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final invitation in sent) ...[
                    _InvitationRow(
                      invitation: invitation,
                      onWithdraw: invitation.open ? () => _withdraw(invitation) : null,
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({required this.invitation, this.onWithdraw});

  final Invitation invitation;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    // Four states, and the reason it stopped being usable is worth saying.
    // "Not available" would leave somebody wondering whether to send it again.
    final (label, fg, bg) = switch (invitation) {
      final i when i.claimed => (l.invitationClaimed, c.ok, c.okSoft),
      final i when i.revoked => (l.invitationRevoked, c.inkFaint, c.surfaceSunken),
      final i when i.expired => (l.invitationExpired, c.caution, c.cautionSoft),
      _ => (l.invitationOpen, c.accent, c.accentSoft),
    };

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invitation.description,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: Space.sm),
              TonedChip(label: label, fg: fg, bg: bg, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            invitation.email,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 13.5, color: c.inkSoft),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              // The code stays readable even once it is spent, because the
              // person who sent it is matching it against a message they wrote.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  invitation.code,
                  style: Type.mono.copyWith(
                    fontSize: 15,
                    color: invitation.open ? c.ink : c.inkFaint,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (invitation.open)
                IconButton(
                  tooltip: l.copyTheMessage,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: invitation.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.copied)),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: IconSize.md),
                ),
              if (onWithdraw != null)
                TextButton(onPressed: onWithdraw, child: Text(l.withdraw)),
            ],
          ),
        ],
      ),
    );
  }
}
