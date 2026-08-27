import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invitations_screen.dart';

/// The code, and the message to send with it.
///
/// TrustIQ does not email the other person. Writing to a stranger on somebody
/// else's behalf is a different product with different obligations, and it
/// would need a mail provider this build does not have. So the person who
/// wants the contract sends it themselves, over whatever they already use.
/// In this market that is almost always WhatsApp.
///
/// The whole message is offered rather than just the code, because a bare
/// eight characters pasted into a chat reads like a scam.
class InvitationCreatedScreen extends StatelessWidget {
  const InvitationCreatedScreen({
    super.key,
    required this.invitation,
    required this.state,
  });

  final Invitation invitation;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    final message = l.invitationMessage(
      invitation.description,
      formatAed(invitation.amount),
      invitation.email,
      invitation.code,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.invitationSent)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.lg, Space.md, Space.lg, Space.section),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.invitationCodeIs,
                  style: Type.caption.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Space.sm),
                // Never mirrored. A code read back right to left is a
                // different code, and somebody will be comparing it character
                // by character against a message on another screen.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    invitation.code,
                    style: Type.mono.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  invitation.email,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 14, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.copied)),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: IconSize.md),
            label: Text(l.copyTheMessage),
          ),
          const SizedBox(height: Space.md),
          InfoCard(
            lift: false,
            child: Text(
              message,
              style: TextStyle(fontSize: 14, height: 1.6, color: c.inkSoft),
            ),
          ),
          const SizedBox(height: Space.lg),
          RuleNote(l.invitationShareNote, icon: Icons.send_outlined),
          const SizedBox(height: Space.sm),
          RuleNote(l.invitationBoundNote(invitation.email), icon: Icons.lock_outline),
          const SizedBox(height: Space.sm),
          RuleNote(l.invitationExpiryNote, icon: Icons.schedule),
          const SizedBox(height: Space.lg),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => InvitationsScreen(state: state),
              ),
            ),
            child: Text(l.invitations),
          ),
        ],
      ),
    );
  }
}
