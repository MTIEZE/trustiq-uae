import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/demo_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'contract_detail_screen.dart';
import 'new_contract_screen.dart';

class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final needsYou = state.contracts
        .where((c) => state.actionsFor(c).any(_isWaitingOnYou))
        .toList();
    final rest = state.contracts.where((c) => !needsYou.contains(c)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Contracts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          // Only in the demo. Against a real project the side you are on comes
          // from your session and cannot be chosen, and offering the control
          // anyway would suggest otherwise.
          if (!state.isLive) _RoleSwitch(state: state),
          if (state.isLive)
            IconButton(
              tooltip: 'Sign out of ${state.backendLabel}',
              onPressed: state.signOut,
              icon: const Icon(Icons.logout, size: 20),
            ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NewContractScreen(state: state),
          ),
        ),
        backgroundColor: TrustIqColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New contract'),
      ),
      body: RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!state.isLive) ...[
            const RuleNote(
              'Demo data. Nothing on this screen is stored anywhere, and no '
              'contract here exists outside this app.',
              icon: Icons.science_outlined,
            ),
            const SizedBox(height: 14),
          ],
          if (state.error != null) ...[
            _ErrorNote(message: state.error!, onDismiss: state.clearError),
            const SizedBox(height: 14),
          ],
          if (needsYou.isNotEmpty) ...[
            const SectionLabel('Waiting on you'),
            const SizedBox(height: 10),
            for (final c in needsYou) ...[
              _ContractTile(contract: c, state: state, highlight: true),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
          const SectionLabel('All contracts'),
          const SizedBox(height: 10),
          for (final c in rest) ...[
            _ContractTile(contract: c, state: state),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const RuleNote(
            'TrustIQ does not hold your money in v1. Payment happens directly '
            'between you and the other party; what is tracked here is the '
            'agreement, the delivery and the evidence.',
            icon: Icons.account_balance_outlined,
          ),
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

class _RoleSwitch extends StatelessWidget {
  const _RoleSwitch({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Demo only: switch which side of the contracts you are viewing',
      child: SegmentedButton<Role>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        segments: const [
          ButtonSegment(value: Role.buyer, label: Text('Buyer')),
          ButtonSegment(value: Role.seller, label: Text('Seller')),
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
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final counterparty = contract.counterpartyFor(state.roleOn(contract));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlight ? TrustIqColors.accent : TrustIqColors.rule,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContractDetailScreen(
              contractId: contract.id,
              state: state,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      contract.description,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  StateChip(contract.state),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'with ${counterparty.name}',
                      style: const TextStyle(fontSize: 13, color: TrustIqColors.inkSoft),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  MoneyText(
                    contract.totalAmount,
                    style: const TextStyle(fontSize: 15),
                    emphasis: true,
                  ),
                ],
              ),
              Text(
                contract.reference,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: TrustIqColors.inkFaint,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: TrustIqColors.critical.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TrustIqColors.critical.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: TrustIqColors.critical),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: TrustIqColors.critical),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: TrustIqColors.critical),
          ),
        ],
      ),
    );
  }
}
