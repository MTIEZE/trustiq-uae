import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// Contrast, measured rather than eyeballed.
///
/// A dark palette is easy to make and easy to make unreadable, and the failure
/// mode is quiet: it looks fine to whoever picked the colours, on their screen,
/// in their room. These are the WCAG ratios, so the question has an answer.

double _luminance(Color c) {
  double channel(double v) {
    final s = v;
    return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = max(la, lb);
  final lo = min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final palettes = {'light': TrustIqPalette.light, 'dark': TrustIqPalette.dark};

  group('text is readable on both sides', () {
    palettes.forEach((name, c) {
      test('$name: body text clears AA on every surface', () {
        for (final surface in [c.surface, c.ground, c.surfaceSunken]) {
          expect(
            contrast(c.ink, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name ink on ${surface.toARGB32().toRadixString(16)}',
          );
        }
      });

      test('$name: secondary text clears AA', () {
        expect(contrast(c.inkSoft, c.surface), greaterThanOrEqualTo(4.5), reason: name);
      });

      test('$name: the faintest text still clears AA for large text', () {
        // inkFaint carries labels and captions, which are small, so this is
        // the one that most wants checking. 3:1 is the large-text floor and
        // the honest bar for a 11px uppercase label.
        expect(contrast(c.inkFaint, c.surface), greaterThanOrEqualTo(3.0), reason: name);
      });

      test('$name: the accent is legible as text on a surface', () {
        // It is used for links and for the emphasis inside notes, so it has to
        // survive as text and not only as a fill.
        expect(contrast(c.accent, c.surface), greaterThanOrEqualTo(3.0), reason: name);
      });

      test('$name: every state colour reads on its own tint', () {
        final pairs = {
          'ok': (c.ok, c.okSoft),
          'caution': (c.caution, c.cautionSoft),
          'critical': (c.critical, c.criticalSoft),
          'accent': (c.accent, c.accentSoft),
        };
        pairs.forEach((label, pair) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(3.0),
            reason: '$name $label chip',
          );
        });
      });
    });
  });

  group('the two sides are actually different', () {
    test('dark is darker', () {
      expect(_luminance(TrustIqPalette.dark.ground),
          lessThan(_luminance(TrustIqPalette.light.ground)));
      expect(_luminance(TrustIqPalette.dark.ink),
          greaterThan(_luminance(TrustIqPalette.light.ink)));
    });

    test('emphasis means more light in the dark, and less in the light', () {
      // accentStrong is the emphasis of accent. On white that means darker; on
      // near-black it has to mean lighter, or emphasis disappears.
      expect(_luminance(TrustIqPalette.light.accentStrong),
          lessThan(_luminance(TrustIqPalette.light.accent)));
      expect(_luminance(TrustIqPalette.dark.accentStrong),
          greaterThan(_luminance(TrustIqPalette.dark.accent)));
    });

    test('a surface still lifts off its ground on both sides', () {
      // If these match, cards vanish and the whole layout goes flat.
      for (final c in palettes.values) {
        expect(c.surface, isNot(equals(c.ground)));
      }
    });
  });

  group('the theme carries the palette', () {
    testWidgets('a widget reads the palette for the brightness it is under',
        (tester) async {
      late TrustIqPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(TrustIqPalette.light),
          darkTheme: buildTheme(TrustIqPalette.dark),
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              seen = context.c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.isDark, isTrue);
      expect(seen.ground, TrustIqPalette.dark.ground);
    });

    testWidgets('a widget with no TrustIQ theme above it still gets a palette',
        (tester) async {
      // Better a light palette than a crash. A screen mounted in a test or a
      // preview without the app around it should still render.
      late TrustIqPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.isDark, isFalse);
    });
  });

  group('state styles', () {
    test('every transaction state has a label and a readable pair', () {
      for (final c in palettes.values) {
        for (final state in TransactionState.values) {
          final style = transactionStateStyle(state, c);
          expect(style.label, isNotEmpty, reason: state.name);
          // Never the wire value: a party should not be shown
          // `pending_acceptance`.
          expect(style.label, isNot(contains('_')), reason: state.name);
          expect(
            contrast(style.fg, style.bg),
            greaterThanOrEqualTo(3.0),
            reason: '${c.isDark ? 'dark' : 'light'} ${state.name}',
          );
        }
      }
    });
  });
}
