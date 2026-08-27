// Draws the launcher icons from the mark the app already draws.
//
//   flutter test tool/generate_launcher_icons.dart
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
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/brand.dart';

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

void main() {
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
}
