import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/language_button.dart';
import 'contract_detail_screen.dart';
import 'new_contract_screen.dart';
import 'invitations_screen.dart';
import 'onboarding_screen.dart';
import 'verify_identity_screen.dart';

class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final needsYou = state.contracts
        .where((c) => state.actionsFor(c).any(_isWaitingOnYou))
        .toList();
    final rest = state.contracts.where((c) => !needsYou.contains(c)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.contracts),
        actions: [
          // Only in the demo. Against a real project the side you are on comes
          // from your session and cannot be chosen, and offering the control
          // anyway would suggest otherwise.
          const LanguageButton(compact: true),
          if (!state.isLive) _RoleSwitch(state: state),
          if (state.isLive)
            IconButton(
              tooltip: l.signOutOf(state.backendLabel),
              onPressed: state.signOut,
              icon: const Icon(Icons.logout, size: IconSize.lg),
            ),
          _Menu(state: state),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NewContractScreen(state: state),
          ),
        ),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add),
        label: Text(l.newContract),
      ),
      body: RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          if (!state.isLive) ...[
            RuleNote(l.demoDataNote, icon: Icons.science_outlined),
            const SizedBox(height: 14),
          ],
          if (state.error != null) ...[
            _ErrorNote(message: state.error!, onDismiss: state.clearError),
            const SizedBox(height: 14),
          ],
          // Three states this list can be in, and they used to look the same.
          // An empty list is not a loaded list with nothing in it, and neither
          // is a list still loading.
          if (state.contracts.isEmpty && state.loading)
            const _Loading()
          else if (state.contracts.isEmpty)
            const _NoContractsYet()
          else ...[
            if (needsYou.isNotEmpty) ...[
              SectionLabel(l.waitingOnYou),
              const SizedBox(height: 10),
              for (final c in needsYou) ...[
                _ContractTile(contract: c, state: state, highlight: true),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
            ],
            SectionLabel(needsYou.isEmpty ? l.yourContracts : l.everythingElse),
            const SizedBox(height: 10),
            for (final c in rest) ...[
              _ContractTile(contract: c, state: state),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 8),
          RuleNote(l.noEscrowNote, icon: Icons.account_balance_outlined),
        ],
        ),
      ),
    );
  }

  /// An action that moves the contract forward, as opposed to one that walks
  /// away from it. Only the former means the contract is genuinely blocked on
  /// this person.
  static bool _isWaitingOnYou(TransactionEvent event) => switch (event) {
        TransactionEvent.accept ||
        TransactionEvent.confirmDelivery ||
        TransactionEvent.markDelivered ||
        TransactionEvent.submit =>
          true,
        _ => false,
      };
}

/// The two things a person needs and could not reach from here.
///
/// The explanation of what TrustIQ is had nowhere to live after the first
/// launch, and identity verification could only be reached from a contract
/// that had already refused to activate. Somebody who wants to be ready
/// before their first contract had no way to be.
class _Menu extends StatelessWidget {
  const _Menu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_vert, size: IconSize.lg),
      onSelected: (choice) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => switch (choice) {
            0 => const OnboardingScreen(),
            1 => VerifyIdentityScreen(state: state),
            _ => InvitationsScreen(state: state),
          },
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 0,
          child: _MenuRow(icon: Icons.help_outline, label: l.howItWorks),
        ),
        PopupMenuItem(
          value: 1,
          child: _MenuRow(icon: Icons.badge_outlined, label: l.yourIdentity),
        ),
        PopupMenuItem(
          value: 2,
          child: _MenuRow(icon: Icons.mail_outline, label: l.invitations),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: IconSize.md, color: context.c.inkSoft),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _RoleSwitch extends StatelessWidget {
  const _RoleSwitch({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l.demoRoleSwitchTooltip,
      child: SegmentedButton<Role>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        segments: [
          ButtonSegment(value: Role.buyer, label: Text(context.l.viewAsBuyer)),
          ButtonSegment(value: Role.seller, label: Text(context.l.viewAsSeller)),
        ],
        selected: {state.viewingAs},
        showSelectedIcon: false,
        onSelectionChanged: (s) => state.viewAs(s.first),
      ),
    );
  }
}

class _ContractTile extends StatelessWidget {
  const _ContractTile({
    required this.contract,
    required this.state,
    this.highlight = false,
  });

  final Contract contract;
  final AppState state;

  /// This contract is waiting on the person reading the screen.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final counterparty = contract.counterpartyFor(state.roleOn(contract));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: c.lift,
      ),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContractDetailScreen(contractId: contract.id, state: state),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.rule),
            ),
            // A Stack, not a Row with a stretched rail. A Row that stretches
            // inside a list has no height to stretch to, and asking for one is
            // how you get an infinite constraint.
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    highlight ? Space.xl : Space.lg,
                    Space.lg,
                    Space.lg,
                    Space.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              contract.description,
                              style: Type.bodyStrong.copyWith(fontSize: 15.5, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          // The amount leads the right-hand column: it is the
                          // first thing anyone looks for in a list of deals.
                          MoneyText(contract.totalAmount, emphasis: true),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: IconSize.sm, color: c.inkFaint),
                          const SizedBox(width: Space.inline),
                          Flexible(
                            child: Text(
                              counterparty.name,
                              style: Type.small.copyWith(color: c.inkSoft),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (counterparty.verified) ...[
                            const SizedBox(width: Space.inline),
                            Icon(Icons.verified, size: IconSize.sm, color: c.accent),
                          ],
                          const Spacer(),
                          const SizedBox(width: Space.sm),
                          StateChip(contract.state, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
                // Marks the row without turning the whole card into a warning,
                // which a coloured border all the way round does.
                if (highlight)
                  // Directional, so in Arabic the rail runs down the right
                  // edge, which is where a reader's eye starts.
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(Radii.lg)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Something the backend refused, shown where it happened rather than as a
/// snackbar that has already gone by the time anyone looks up.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: c.critical.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.critical.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: IconSize.md, color: c.critical),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: c.critical),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: c.critical),
          ),
        ],
      ),
    );
  }
}


/// The list while it is still being fetched.
///
/// Distinct from an empty list on purpose. Showing "no contracts yet" for the
/// second it takes to load tells a returning person their contracts are gone.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

/// The first thing a new person sees, so it says what to do rather than
/// reporting that there is nothing.
class _NoContractsYet extends StatelessWidget {
  const _NoContractsYet();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 48, bottom: 24),
      child: Column(
        children: [
          Icon(Icons.description_outlined, size: IconSize.hero, color: c.inkFaint.withValues(alpha: 0.5)),
          const SizedBox(height: Space.lg),
          Text(context.l.noContractsYet, style: Type.heading),
          const SizedBox(height: Space.sm),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.xxl),
            child: Text(
              context.l.noContractsBlurb,
              textAlign: TextAlign.center,
              style: Type.small.copyWith(color: c.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
