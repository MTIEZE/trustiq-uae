import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'contract_detail_screen.dart';
import 'dispute_screen.dart';

/// What has happened on your contracts, and what is waiting on you.
///
/// Built from the contract record itself rather than from a separate stream of
/// messages, so it can only ever say things that actually happened. There is
/// no marketing in this list and no room for any: every line is one recorded
/// transition, rendered from the event and the role that fired it.
///
/// The two halves are separated because they are different kinds of thing. One
/// is a task list. The other is news, and news that sits above a task is a
/// task somebody misses.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  void initState() {
    super.initState();
    // Marked read on opening rather than on tapping each line: the whole list
    // is on screen, and asking somebody to dismiss fifteen things one by one
    // is how a notification centre becomes a place people stop going.
    widget.state.markActivityRead();
  }

  void _open(AppNotification n) {
    final contractId = n.contractId;
    if (contractId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => n.disputeId != null
            ? DisputeScreen(contractId: contractId, state: widget.state)
            : ContractDetailScreen(contractId: contractId, state: widget.state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.notifications)),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final all = widget.state.activity;
          final waiting = all.where((n) => n.needsYou).toList();
          final news = all.where((n) => !n.needsYou).toList();

          if (all.isEmpty) return _Empty();

          return RefreshIndicator(
            onRefresh: widget.state.loadActivity,
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg, Space.md, Space.lg, Space.section),
              children: [
                if (waiting.isNotEmpty) ...[
                  SectionLabel(l.needsYou),
                  const SizedBox(height: Space.sm),
                  for (final n in waiting) ...[
                    _Line(notification: n, onTap: () => _open(n)),
                    const SizedBox(height: Space.sm),
                  ],
                  const SizedBox(height: Space.lg),
                ],
                if (news.isNotEmpty) ...[
                  SectionLabel(l.history),
                  const SizedBox(height: Space.sm),
                  for (final n in news) ...[
                    _Line(notification: n, onTap: () => _open(n)),
                    const SizedBox(height: Space.sm),
                  ],
                ],
                const SizedBox(height: Space.md),
                RuleNote(l.activityNote, icon: Icons.receipt_long_outlined),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: IconSize.hero, color: c.inkFaint),
            const SizedBox(height: Space.lg),
            Text(
              l.nothingWaiting,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.sm),
            Text(
              l.nothingWaitingBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.55, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;

    // The two machines share event names, so which one it came from is what
    // decides how the name is read. Getting this wrong would not throw; it
    // would render a plausible sentence about the wrong thing.
    final text = notification.aboutDispute
        ? describeDisputeEvent(
            DisputeEvent.fromWire(notification.event), notification.actor, l)
        : describeEvent(
            TransactionEvent.fromWire(notification.event), notification.actor, l);

    return InfoCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 3, end: 12),
                child: Icon(
                  notification.needsYou
                      ? Icons.pending_actions_outlined
                      : Icons.history,
                  size: IconSize.lg,
                  color: notification.needsYou ? c.accent : c.inkFaint,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight:
                            notification.unread ? FontWeight.w600 : FontWeight.w400,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoment(notification.at, Localizations.localeOf(context)),
                      style: Type.caption.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: IconSize.md, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
