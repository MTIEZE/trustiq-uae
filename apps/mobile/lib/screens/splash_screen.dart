import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand.dart';

/// The first second and a bit.
///
/// Tapping the icon used to give a white rectangle and then, abruptly, the
/// introduction. White is not one of this app's colours, so the flash read as
/// something loading badly rather than as an app opening.
///
/// What plays instead is the product's own gesture. TrustIQ seals a record, so
/// the mark arrives the way a stamp does: the edge meets the paper first, the
/// ink follows, and the check is drawn last because agreeing is a separate act
/// from stamping. The wordmark rises under it once the seal has landed.
///
/// It is short on purpose. Somebody opening this for the twentieth time is not
/// enjoying the animation, and a launch sequence that has to be sat through is
/// a tax collected on every use. Twelve hundred milliseconds, overlapping the
/// session restore that was happening anyway, so most of it is time the app
/// was going to spend regardless.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _run = Duration(milliseconds: 1200);

  /// Where in the run the seal lands. The press, the bloom and the ring all
  /// key off this so the impact is one event rather than three near misses.
  static const _impact = 0.42;

  late final AnimationController _c = AnimationController(vsync: this, duration: _run);

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) _handOver();
    });
    // Started from didChangeDependencies instead, once the reduced-motion
    // setting can be read.
  }

  bool _started = false;
  bool _handed = false;

  /// Leaves, once, and never from inside a build.
  ///
  /// Both of those were real. Setting the controller to its end value fires
  /// the completed status, so the reduced-motion path handed over twice; and
  /// it does that from didChangeDependencies, where the parent's setState is
  /// an error rather than a rebuild.
  void _handOver() {
    if (_handed) return;
    _handed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Somebody who has asked their phone to stop animating things has asked
    // this too. They get the finished mark and a hand-off, not a shorter
    // version of the same performance.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      _handOver();
      return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      // Flat, and exactly the colour Android already painted the window with
      // before Flutter existed. The seam between the two is meant to be
      // impossible to see; everything with any light in it arrives after.
      backgroundColor: c.ground,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;

            // The press. It comes down from slightly too big and lands on the
            // impact, not near it, which is the whole reason the ring and the
            // bloom are keyed off the same number.
            final press = 1.0 + 0.10 * (1 - Curves.easeOutCubic.transform(
              (t / _impact).clamp(0.0, 1.0)));

            // The light the seal throws. It blooms as the stamp lands and then
            // settles back, because a glow that only ever grows reads as a
            // loading screen rather than as something having happened.
            final rise = Curves.easeOutCubic.transform(
              ((t - 0.22) / (_impact - 0.22)).clamp(0.0, 1.0));
            final settle = Curves.easeOutCubic.transform(
              ((t - _impact) / 0.30).clamp(0.0, 1.0));
            final glow = rise * (1 - 0.42 * settle);

            // One ring, outward, once. Anything repeating would be a spinner.
            final ring = Curves.easeOutCubic.transform(
              ((t - _impact) / 0.40).clamp(0.0, 1.0));

            // The wordmark waits for the seal to have landed. Anything sooner
            // and the two read as one thing arriving twice.
            final word = Curves.easeOutCubic.transform(
              ((t - 0.66) / 0.32).clamp(0.0, 1.0));

            const bleed = IconSize.launch * 1.3;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  // The mark sizes this; the glow bleeds well past it and must
                  // not be trimmed back to the mark's own box.
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -bleed,
                      right: -bleed,
                      top: -bleed,
                      bottom: -bleed,
                      child: CustomPaint(
                        painter: _ImpactPainter(glow: glow, ring: ring, colour: c.accent),
                      ),
                    ),
                    Transform.scale(
                      scale: press,
                      child: TrustIqMark(size: IconSize.launch, struck: t),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                Opacity(
                  opacity: word,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - word)),
                    child: TrustIqWordmark(fontSize: 30),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The light around the seal, and the single ring the strike sends out.
///
/// Drawn behind the mark rather than inside it, because `TrustIqMark` is the
/// app icon and a logo in six other places, and none of those wants a halo.
class _ImpactPainter extends CustomPainter {
  _ImpactPainter({required this.glow, required this.ring, required this.colour});

  final double glow;
  final double ring;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    if (glow > 0) {
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: 0.26 * glow),
              colour.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: r)),
      );
    }

    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        centre,
        r * (0.34 + 0.62 * ring),
        Paint()
          ..color = colour.withValues(alpha: 0.32 * (1 - ring))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + 2.2 * (1 - ring),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ImpactPainter old) =>
      old.glow != glow || old.ring != ring || old.colour != colour;
}
