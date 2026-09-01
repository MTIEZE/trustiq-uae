// Draws the launcher icons from the mark the app already draws.
//
//   flutter test tool/generate_launcher_icons.dart
//
// Writes the five launcher densities into android/, and the two images Play
// asks for into store/. All of them from TrustIqMark, so the icon on the home
// screen, the icon on the store page and the mark inside the app are one
// definition rather than three files that agree today.
//
// Not part of the test suite. It lives here rather than in test/ so a normal
// `flutter test` does not rewrite five PNGs every time somebody runs it, and it
// is run by hand when the mark changes.
//
// Why generate rather than export from a design tool: TrustIqMark is a painter,
// not an image, so the icon on the home screen and the mark inside the app can
// never drift apart. There is one definition of the shape and this reads it.
//
// It is a test file because that is the only way to get a real Flutter canvas
// without launching a device. Nothing here asserts anything.
//
// One density per test, and the encoding inside runAsync. The test binding
// runs on fake time, and toImage needs the real event loop: doing it inline
// completes once and then hangs forever on the second pass, which is exactly
// what the first version of this did.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/brand.dart';

import 'fonts.dart';

/// Android's legacy launcher densities.
const _densities = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// How much of the square the mark fills.
///
/// Launchers crop and mask icons differently, and a mark drawn edge to edge
/// loses its corners on any device that rounds them. The meaningful part stays
/// inside roughly the middle two thirds.
const _fill = 0.62;

/// Renders one widget to a PNG of exactly [width] by [height].
///
/// The encoding goes inside runAsync because the test binding runs on fake
/// time and toImage needs the real event loop: done inline it completes once
/// and then hangs forever on the second call.
Future<void> _render(
  WidgetTester tester,
  String path,
  double width,
  double height,
  Widget child,
) async {
  final key = GlobalKey();

  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(key: key, child: SizedBox(width: width, height: height, child: child)),
  );
  await tester.pump();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  late final List<int> png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    png = data!.buffer.asUint8List();
  });

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png);

  // ignore: avoid_print
  print('  $path -> ${png.length} bytes');
}

/// A host with the theme, because the wordmark reads its colours from it.
///
/// The Material is not decoration. Text with no Material ancestor is painted by
/// Flutter in a deliberate warning style — black on a double yellow underline —
/// and that is exactly what the first feature graphic came out as.
Widget _themed(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(TrustIqPalette.light),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Material(type: MaterialType.transparency, child: child),
    );

void main() {
  // The wordmark on the feature graphic needs a real typeface. Without this
  // the test binding drew it as black blocks under a yellow underline.
  setUp(() async => loadFonts());

  _densities.forEach((folder, side) {
    testWidgets('$folder ${side}x$side', (tester) async {
      final key = GlobalKey();
      final size = side.toDouble();

      tester.view.physicalSize = Size(size, size);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: Container(
            width: size,
            height: size,
            // A ground rather than transparency. A transparent launcher icon
            // takes whatever the wallpaper is behind it, and the mark is a
            // seal: it needs something to be stamped on.
            color: TrustIqPalette.light.ground,
            alignment: Alignment.center,
            child: TrustIqMark(size: size * _fill),
          ),
        ),
      );
      await tester.pump();

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

      late final List<int> png;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        png = data!.buffer.asUint8List();
      });

      final file = File('android/app/src/main/res/$folder/ic_launcher.png');
      file.writeAsBytesSync(png);

      // ignore: avoid_print
      print('  $folder -> ${png.length} bytes');
    });
  });

  // ── What Play asks for ────────────────────────────────────────────────

  testWidgets('store icon 512x512', (tester) async {
    // The same ground and the same fill as the launcher, deliberately. An icon
    // that is tighter or brighter on the store page than on the home screen is
    // a small broken promise on the first screen anybody sees.
    await _render(
      tester,
      'store/icon-512.png',
      512,
      512,
      Container(
        color: TrustIqPalette.light.ground,
        alignment: Alignment.center,
        child: const TrustIqMark(size: 512 * _fill),
      ),
    );
  });

  testWidgets('feature graphic 1024x500', (tester) async {
    // No tagline. Play crops this differently on every surface it appears on
    // and scales it down far enough that a sentence becomes texture, so the
    // only thing on it is the thing that has to survive being small.
    await _render(
      tester,
      'store/feature-1024x500.png',
      1024,
      500,
      _themed(
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 0.95,
              colors: [
                TrustIqPalette.light.accentSoft,
                TrustIqPalette.light.ground,
              ],
            ),
          ),
          child: const Center(child: TrustIqLockup(markSize: 108, fontSize: 62)),
        ),
      ),
    );
  });
}
