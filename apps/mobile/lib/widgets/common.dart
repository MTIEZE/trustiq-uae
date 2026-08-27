import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../theme.dart';

/// A state, shown as both a colour and a word.
///
/// Colour alone is not a label: it fails for anyone who cannot distinguish the
/// hues, and it fails in a screenshot pasted into a support thread. The dot
/// carries the colour so the text can stay dark enough to read, which a tinted
/// label on a tinted ground never quite is.
class StateChip extends StatelessWidget {
  const StateChip(this.state, {super.key, this.compact = false});
  final TransactionState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = transactionStateStyle(state, c);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: style.fg, shape: BoxShape.circle),
          ),
          Text(
            style.label,
            style: TextStyle(
              color: style.fg,
              fontSize: compact ? 11 : 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// An amount, always rendered from fils through the domain formatter.
///
/// The screens never do their own currency arithmetic or string building; that
/// is how a rounding bug reaches a user. The currency is set a size down and
/// in a lighter weight so a column of amounts reads as numbers first.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style, this.emphasis = false});
  final Fils amount;
  final TextStyle? style;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = (style ?? Type.amount).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: emphasis ? c.ink : (style?.color ?? c.ink),
    );
    final text = formatAed(amount);
    final split = text.lastIndexOf(' ');
    if (split == -1) return Text(text, style: base);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, split)),
          TextSpan(
            text: text.substring(split),
            style: base.copyWith(
              fontSize: (base.fontSize ?? 15) * 0.68,
              fontWeight: FontWeight.w600,
              color: c.inkFaint,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      style: base,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text(
      text.toUpperCase(),
      style: Type.label.copyWith(color: color ?? c.inkFaint),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.child, this.padding, this.lift = true});
  final Widget child;
  final EdgeInsets? padding;

  /// Off for a card sitting inside another surface, where a shadow would read
  /// as a second layer that is not there.
  final bool lift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: lift ? c.lift : null,
      ),
      child: Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Space.lg),
          child: child,
        ),
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
        const SizedBox(height: Space.sm),
        child,
      ],
    );
  }
}

/// A short, quiet note explaining a rule the person would otherwise have to
/// guess at. Used where the product does something unusual on purpose.
class RuleNote extends StatelessWidget {
  const RuleNote(this.text, {super.key, this.icon = Icons.info_outline, this.tone});
  final String text;
  final IconData icon;

  /// Overrides the accent, for a note that is a warning rather than an
  /// explanation. Rare on purpose: most of these are the product being
  /// deliberately unusual, not something going wrong.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colour = tone ?? c.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              text,
              style: Type.small.copyWith(fontSize: 12.5, color: c.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading with room around it, so a long screen has a rhythm rather than a
/// single unbroken column of cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md, left: Space.xs),
      child: Row(
        children: [
          Expanded(child: SectionLabel(label)),
          ?trailing,
        ],
      ),
    );
  }
}
