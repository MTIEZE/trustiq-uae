import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../theme.dart';

/// A state, shown as both a colour and a word.
///
/// Colour alone is not a label: it fails for anyone who cannot distinguish the
/// hues, and it fails in a screenshot pasted into a support thread.
class StateChip extends StatelessWidget {
  const StateChip(this.state, {super.key});
  final TransactionState state;

  @override
  Widget build(BuildContext context) {
    final style = transactionStateStyle(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// An amount, always rendered from fils through the domain formatter.
///
/// The screens never do their own currency arithmetic or string building; that
/// is how a rounding bug reaches a user.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style, this.emphasis = false});
  final Fils amount;
  final TextStyle? style;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatAed(amount),
      style: (style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
        color: emphasis ? TrustIqColors.ink : null,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: TrustIqColors.inkFaint,
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class LabelledValue extends StatelessWidget {
  const LabelledValue({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// A short, quiet note explaining a rule the person would otherwise have to
/// guess at. Used where the product does something unusual on purpose.
class RuleNote extends StatelessWidget {
  const RuleNote(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TrustIqColors.ground,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: TrustIqColors.accent, width: 2.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: TrustIqColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: TrustIqColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
