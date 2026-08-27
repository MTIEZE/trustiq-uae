import 'package:flutter/material.dart';

import '../data/language.dart';
import '../theme.dart';

/// Makes the language controller reachable from any screen.
///
/// An InheritedNotifier rather than passing the controller down through six
/// constructors, because the sign-in screen needs it as much as the settings
/// do and there is no shared ancestor between them but the app.
class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({super.key, required LanguageController controller, required super.child})
      : super(notifier: controller);

  static LanguageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}

/// Switches between the two languages.
///
/// Deliberately present on the sign-in screen and not only in settings.
/// Someone who cannot read the language the app opened in has to be able to
/// change it before they have an account, and burying it behind a signed-in
/// screen would be the one place they cannot reach.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.compact = false});

  /// For an app bar, where the label would crowd the title.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = LanguageScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    final c = context.c;
    final l = context.l;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    // Each option names itself in its own script, so the label a person is
    // looking for is legible even when the current language is not.
    final other = isArabic ? l.languageEnglish : l.languageArabic;

    return TextButton.icon(
      onPressed: () => controller.set(Locale(isArabic ? 'en' : 'ar')),
      icon: Icon(Icons.translate, size: IconSize.md, color: c.inkSoft),
      label: Text(other, style: Type.caption.copyWith(color: c.inkSoft, fontSize: 13)),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: compact ? Space.sm : Space.md,
          vertical: Space.xs,
        ),
        foregroundColor: c.inkSoft,
      ),
    );
  }
}
