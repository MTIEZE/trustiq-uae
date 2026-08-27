import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
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

  group('the typeface', () {
    for (final palette in [TrustIqPalette.light, TrustIqPalette.dark]) {
      final side = palette.isDark ? 'dark' : 'light';

      test('$side: every text style in the theme carries the bundled family', () {
        // Set in one place so there is no second place to forget it. A screen
        // that quietly falls back to the platform font is the kind of thing
        // nobody notices until a screenshot goes out.
        final theme = buildTheme(palette);
        expect(theme.textTheme.bodyMedium?.fontFamily, kFontFamily, reason: side);
        expect(theme.textTheme.titleLarge?.fontFamily, kFontFamily, reason: side);
        expect(theme.textTheme.labelSmall?.fontFamily, kFontFamily, reason: side);
      });
    }

    testWidgets('a widget under the app inherits it', (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(TrustIqPalette.light),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                style = DefaultTextStyle.of(context).style;
                return const Text('x');
              },
            ),
          ),
        ),
      );
      expect(style.fontFamily, kFontFamily);
    });

    test('amounts are set with tabular figures', () {
      // Digits that do not line up down a column make a list of amounts hard
      // to compare, which is most of what these screens are for.
      for (final style in [Type.amount, Type.amountLarge]) {
        expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
    });

    test('a fingerprint stays monospace', () {
      // It has to be comparable character by character, which a proportional
      // face makes needlessly hard.
      expect(Type.mono.fontFamily, 'monospace');
    });
  });

  group('nothing paints a colour of its own', () {
    // The drift guard. A hardcoded colour looks right in whichever theme its
    // author had open and wrong in the other, and nobody notices until someone
    // switches. Four spinners were painting themselves white, which reads as
    // white-on-light-teal the moment the dark theme is on.
    //
    // The mark is exempt: a logo that changes colour with the interface is not
    // a logo.
    final screens = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('theme.dart'))
        .where((f) => !f.path.endsWith('brand.dart'))
        .toList();

    test('there are screens to check', () {
      expect(screens.length, greaterThan(5));
    });

    for (final file in screens) {
      test('${file.uri.pathSegments.last} uses only the palette', () {
        final offenders = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          // Colors.transparent has no light or dark version to get wrong.
          final cleaned = line.replaceAll('Colors.transparent', '');
          if (RegExp(r'Colors\.[a-z]').hasMatch(cleaned) ||
              RegExp(r'Color\(0x').hasMatch(cleaned)) {
            offenders.add('  line ${i + 1}: ${line.trim()}');
          }
        }
        expect(
          offenders,
          isEmpty,
          reason: 'use context.c instead of a literal colour: '
              '${offenders.join(" | ")}',
        );
      });
    }
  });

  group('what sits on the accent', () {
    for (final c in [TrustIqPalette.light, TrustIqPalette.dark]) {
      final side = c.isDark ? 'dark' : 'light';
      test('$side: a label on a filled button is readable', () {
        // The dark accent is a light teal. White on it fails, which is exactly
        // what four widgets were doing before onAccent existed.
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5), reason: side);
      });
    }
  });

  group('the scales are actually used', () {
    // The other half of the drift guard. A design system nobody follows is a
    // file, not a system, and the way it stops being followed is one hardcoded
    // 13 at a time.
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('theme.dart'))
        .where((f) => !f.path.endsWith('brand.dart'))
        .toList();

    for (final file in sources) {
      test('${file.uri.pathSegments.last} sizes its icons off the scale', () {
        // There were ten icon sizes across the screens. The differences
        // between most of them are invisible and the inconsistency is not.
        final offenders = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (RegExp(r'size: [0-9]').hasMatch(lines[i])) {
            offenders.add('line ${i + 1}');
          }
        }
        expect(offenders, isEmpty, reason: 'use IconSize: ${offenders.join(', ')}');
      });
    }

    test('the scales have no accidental duplicates', () {
      final spacing = [Space.xs, Space.inline, Space.sm, Space.md, Space.lg, Space.xl, Space.xxl, Space.section];
      expect(spacing.toSet().length, spacing.length);
      // And they climb, so picking "the next one up" is meaningful.
      for (var i = 1; i < spacing.length; i += 1) {
        expect(spacing[i], greaterThan(spacing[i - 1]));
      }

      final icons = [IconSize.sm, IconSize.md, IconSize.lg, IconSize.xl, IconSize.hero];
      expect(icons.toSet().length, icons.length);
      for (var i = 1; i < icons.length; i += 1) {
        expect(icons[i], greaterThan(icons[i - 1]));
      }
    });
  });

  group('state styles', () {
    testWidgets('every transaction state has a label and a readable pair',
        (tester) async {
      // Needs a context now that the labels are translated, and it is worth
      // running for both languages: a state whose Arabic label is empty would
      // otherwise ship as a blank chip.
      for (final locale in LanguageController.supported) {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: locale,
            home: Builder(builder: (context) {
              ctx = context;
              return const SizedBox();
            }),
          ),
        );
        final l = L.of(ctx);

        for (final c in palettes.values) {
        for (final state in TransactionState.values) {
          final style = transactionStateStyle(state, c, l);
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
      }
    });

    testWidgets('every label in both languages is filled in', (tester) async {
      // A missing translation renders as an empty chip rather than as an
      // error, which is the kind of thing that ships.
      for (final locale in LanguageController.supported) {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: locale,
            home: Builder(builder: (context) {
              ctx = context;
              return const SizedBox();
            }),
          ),
        );
        final l = L.of(ctx);
        final code = locale.languageCode;

        for (final e in TransactionEvent.values) {
          expect(transactionEventLabel(e, l).trim(), isNotEmpty, reason: '$code ${e.name}');
        }
        for (final d in DisputeState.values) {
          expect(disputeStateLabel(d, l).trim(), isNotEmpty, reason: '$code ${d.name}');
        }
        for (final d in ResolutionDecision.values) {
          expect(decisionLabel(d, l).trim(), isNotEmpty, reason: '$code ${d.name}');
        }
      }
    });
  });
}
