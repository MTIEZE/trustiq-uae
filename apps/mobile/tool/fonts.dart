// Fonts, for the tools that render the app to a file.
//
// Shared because both of them need it and only one of them had it. The icon
// generator drew its feature graphic with the wordmark as black blocks under a
// yellow underline, which is what a test binding does with text it has no font
// for, and the fix already existed twenty lines away in the other file.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every font the app declares, including the one it does not declare.
///
/// A test binding ships with no fonts at all, so the first version of this
/// loaded IBM Plex by hand and produced screens where every single icon was an
/// empty square. Material Icons is not in pubspec because `uses-material-design`
/// puts it in the bundle, and the bundle is where this now reads from, so
/// nothing has to be listed twice.
Future<void> loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
