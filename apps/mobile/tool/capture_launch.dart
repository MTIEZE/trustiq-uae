// Renders the launch sequence to PNGs so it can be looked at.
//
//   flutter test tool/capture_launch.dart --update-goldens
//
// Not part of the suite, and the images it writes are not committed. There is
// nothing to compare them against: test/launch_test.dart asserts the sequence
// behaves, and no assertion can tell you whether it is any good to watch,
// which was the actual complaint. These are for looking at.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/screens/splash_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/brand.dart';

Future<void> loadFonts() async {
  final loader = FontLoader('IBMPlexSans');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/IBMPlexSans-$weight.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

void main() {
  setUp(() async => loadFonts());

  Future<void> shoot(WidgetTester tester, String name) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  for (final entry in {'dark': TrustIqPalette.dark, 'light': TrustIqPalette.light}.entries) {
    final palette = entry.value;

    testWidgets('the seal coming down, ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1000, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        home: Scaffold(
          backgroundColor: palette.ground,
          body: Center(
            child: Wrap(
              spacing: 26,
              runSpacing: 26,
              alignment: WrapAlignment.center,
              children: [
                for (final t in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
                  TrustIqMark(size: 76, struck: t),
              ],
            ),
          ),
        ),
      ));
      await shoot(tester, 'strip_${entry.key}');
    });

    testWidgets('the screen itself, ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        home: SplashScreen(onDone: () {}),
      ));

      // Four moments across the run, captured as they actually arrive.
      var elapsed = Duration.zero;
      for (final at in [300, 500, 700, 900, 1200]) {
        final step = Duration(milliseconds: at) - elapsed;
        elapsed = Duration(milliseconds: at);
        await tester.pump(step);
        await shoot(tester, 'screen_${entry.key}_$at');
      }
    });
  }
}
