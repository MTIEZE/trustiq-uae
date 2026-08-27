import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';

/// Guards on the two languages.
///
/// A missing translation does not throw: it renders as a blank label or as the
/// English string in an Arabic screen, and both ship quietly. These read the
/// ARB files as data, which is the only way to see the gap before a user does.

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final en = _arb('app_en.arb');
  final ar = _arb('app_ar.arb');

  List<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toList()..sort();

  group('the two files say the same things', () {
    test('Arabic covers every English key', () {
      final missing = keys(en).where((k) => !ar.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'untranslated: ${missing.join(', ')}');
    });

    test('Arabic has no key English does not', () {
      // A stray key is a translation of something that no longer exists, or a
      // typo that will never be read.
      final extra = keys(ar).where((k) => !en.containsKey(k)).toList();
      expect(extra, isEmpty, reason: 'orphaned: ${extra.join(', ')}');
    });

    test('nothing is left blank', () {
      for (final arb in [en, ar]) {
        for (final key in keys(arb)) {
          expect((arb[key] as String).trim(), isNotEmpty, reason: key);
        }
      }
    });

    test('every placeholder survives translation', () {
      // A string that interpolates an email in English and drops it in Arabic
      // loses the one piece of information it was carrying.
      final placeholder = RegExp(r'\{(\w+)\}');
      for (final key in keys(en)) {
        final inEn = placeholder.allMatches(en[key] as String).map((m) => m[1]).toSet();
        final inAr = placeholder.allMatches(ar[key] as String).map((m) => m[1]).toSet();
        expect(inAr, inEn, reason: key);
      }
    });

    test('the Arabic file is actually in Arabic', () {
      // Catches a key copied across and never translated. The exceptions are
      // deliberate: the brand, each language naming itself, and codeHint,
      // which is an example of an invitation code rather than a sentence.
      // Codes are generated from a Latin alphabet chosen for being unambiguous
      // when read aloud, so an Arabic example would show somebody characters
      // they will never be asked to type.
      const untranslated = {'appName', 'languageEnglish', 'languageArabic', 'codeHint'};
      final arabic = RegExp(r'[؀-ۿ]');
      for (final key in keys(ar)) {
        if (untranslated.contains(key)) continue;
        expect(arabic.hasMatch(ar[key] as String), isTrue,
            reason: '$key reads as "${ar[key]}"');
      }
    });
  });

  group('the app speaks both', () {
    for (final locale in LanguageController.supported) {
      testWidgets('${locale.languageCode}: the delegates resolve', (tester) async {
        late L l;
        late TextDirection direction;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: locale,
            home: Builder(builder: (context) {
              l = L.of(context);
              direction = Directionality.of(context);
              return const SizedBox();
            }),
          ),
        );
        expect(l.contracts.trim(), isNotEmpty);
        // Arabic reads right to left, and the whole layout follows from this
        // one value rather than from anything the screens do.
        expect(direction, locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      });
    }
  });

  group('nothing is hardcoded on a screen', () {
    // The drift guard for language, the same shape as the one for colour. An
    // English string left in a screen renders as English inside an Arabic
    // interface: no error, no test failure, just one line that did not switch.
    final screens = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('there are screens to check', () => expect(screens.length, greaterThan(5)));

    for (final file in screens) {
      test('${file.uri.pathSegments.last} reads its text from the ARB', () {
        final offenders = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          // A sentence, not an identifier: starts with a capital and runs on.
          for (final m in RegExp(r"'([A-Z][^']{6,})'").allMatches(line)) {
            final value = m.group(1)!;
            if (value.startsWith('package') || value.startsWith('assets')) continue;
            offenders.add('line ${i + 1}: $value');
          }
        }
        expect(offenders, isEmpty, reason: 'move to the ARB: ${offenders.join(' | ')}');
      });
    }
  });

  group('remembering the choice', () {
    test('an unset language follows the device', () {
      final controller = LanguageController.forTests();
      expect(controller.resolved(const Locale('ar')).languageCode, 'ar');
      expect(controller.resolved(const Locale('en')).languageCode, 'en');
      // Anything else lands on English rather than on nothing.
      expect(controller.resolved(const Locale('fr')).languageCode, 'en');
      expect(controller.resolved(null).languageCode, 'en');
    });

    test('a set language wins over the device', () {
      final controller = LanguageController.forTests(const Locale('en'));
      expect(controller.resolved(const Locale('ar')).languageCode, 'en');
    });

    test('exactly two languages are offered', () {
      // Two, and only two. A half-supported third would be worse than none.
      expect(LanguageController.supported.map((l) => l.languageCode).toList(), ['en', 'ar']);
    });
  });
}
