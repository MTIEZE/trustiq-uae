import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/main.dart';
import 'package:trustiq_app/screens/splash_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/brand.dart';

/// What the app looks like in the first second, and whether the seam shows.
void main() {
  group('the Android window matches the app it is about to become', () {
    // The window background is painted by Android before Dart exists, so the
    // colours have to be written down twice. This is the test that stops the
    // second copy drifting, in the same spirit as schema-parity: the duplicate
    // is deliberate, so the check for it has to be real.
    String res(String path) => File('android/app/src/main/res/$path').readAsStringSync();

    int colour(String xml, String name) {
      final m = RegExp('<color name="$name">#([0-9A-Fa-f]{8})</color>').firstMatch(xml);
      expect(m, isNotNull, reason: '$name is not declared');
      return int.parse(m!.group(1)!, radix: 16);
    }

    test('the light launch colour is the light ground', () {
      final xml = res('values/colors.xml');
      expect(colour(xml, 'launch_ground'), TrustIqPalette.light.ground.toARGB32());
    });

    test('the dark launch colour is the dark ground', () {
      final xml = res('values-night/colors.xml');
      expect(colour(xml, 'launch_ground'), TrustIqPalette.dark.ground.toARGB32());
    });

    test('nothing opens on a colour that is not ours', () {
      // The exact two values that were there. A dark phone opening this app
      // flashed white, and the file that looked responsible was not the file
      // being read.
      for (final path in ['drawable/launch_background.xml', 'drawable-v21/launch_background.xml']) {
        final xml = res(path);
        expect(xml, isNot(contains('@android:color/white')), reason: path);
        expect(xml, isNot(contains('?android:colorBackground')), reason: path);
        expect(xml, contains('@color/launch_ground'), reason: path);
      }
    });

    test('both copies of the launch background say the same thing', () {
      expect(res('drawable/launch_background.xml'), res('drawable-v21/launch_background.xml'));
    });

    test('the window behind Flutter is painted too', () {
      // The other end of the seam. Fixing only the splash leaves a white frame
      // when the splash is torn down.
      for (final path in ['values/styles.xml', 'values-night/styles.xml']) {
        expect(res(path), isNot(contains('?android:colorBackground')), reason: path);
      }
    });
  });

  group('the launch sequence', () {
    test('the duration is one somebody would want to sit through', () {
      // Not a style opinion: below this the seal never reads as landing, and
      // above it the sequence is a wait rather than an arrival. Here so that
      // tuning the number stays a decision rather than a slip of a keyboard.
      expect(SplashScreen.run.inMilliseconds, inInclusiveRange(900, 3000));
    });

    Widget wrap(Widget child) => MaterialApp(
          theme: buildTheme(TrustIqPalette.light),
          home: child,
        );

    // Timed as fractions of SplashScreen.run rather than in milliseconds. The
    // duration is the one thing in this file somebody will want to tune, and a
    // test that goes red when they do teaches them to distrust the suite.
    Duration part(double f) =>
        Duration(microseconds: (SplashScreen.run.inMicroseconds * f).round());

    testWidgets('it hands over when it is done, and only then', (tester) async {
      var handed = 0;
      await tester.pumpWidget(wrap(SplashScreen(onDone: () => handed += 1)));

      await tester.pump(part(0.5));
      expect(handed, 0, reason: 'it handed over halfway through');

      await tester.pumpAndSettle();
      expect(handed, 1, reason: 'the app never got out of its own launch screen');
    });

    testWidgets('somebody who turned animations off does not wait', (tester) async {
      var handed = 0;
      await tester.pumpWidget(wrap(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SplashScreen(onDone: () => handed += 1),
        ),
      ));

      // One frame, then the frame the callback is posted to. No 1.2 seconds.
      await tester.pump();
      expect(handed, 1, reason: 'reduced motion still sat through the animation');

      // And they see the finished mark, not a blank screen where it would be.
      expect(tester.widget<TrustIqMark>(find.byType(TrustIqMark)).struck, 1);
    });

    testWidgets('the mark is drawn on the way in, not just at the end', (tester) async {
      await tester.pumpWidget(wrap(SplashScreen(onDone: () {})));

      double struck() => tester.widget<TrustIqMark>(find.byType(TrustIqMark)).struck;

      await tester.pump(part(0.25));
      final early = struck();
      await tester.pump(part(0.30));
      final later = struck();

      expect(early, greaterThan(0));
      expect(later, greaterThan(early), reason: 'the seal is not coming down');
      expect(later, lessThan(1), reason: 'it is over before it looks like anything');

      await tester.pumpAndSettle();
      expect(struck(), 1);
    });

    testWidgets('the app opens on it, then goes on with the app', (tester) async {
      await tester.pumpWidget(TrustIqApp(backend: DemoBackend(), opensWithSplash: true));

      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'the launch sequence is written but nothing shows it');

      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing,
          reason: 'the app never left its launch screen');
    });

    testWidgets('a test tree does not have to sit through it', (tester) async {
      // The default, and the reason every other widget test still passes.
      await tester.pumpWidget(TrustIqApp(backend: DemoBackend()));
      await tester.pump();
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
