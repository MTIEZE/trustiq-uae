import 'dart:math';

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The TrustIQ mark.
///
/// A seal with a check cut into it. Two ideas the product needs to carry at a
/// glance: something was verified, and the record of it is closed. The octagon
/// is a stamp rather than a badge, which is the difference between a document
/// and an award.
///
/// Drawn rather than shipped as an image so it stays sharp at any size and
/// costs nothing to load. It is one path and a stroke.
///
/// Its teal does not follow the theme. A mark that changes colour with the
/// interface is not a mark, and the light accent has enough contrast against
/// both grounds to stay legible on either.
class TrustIqMark extends StatelessWidget {
  const TrustIqMark({super.key, this.size = 44, this.struck = 1});

  final double size;

  /// How far the seal has come down, from 0 to 1.
  ///
  /// Default 1, which is the finished mark, so every place that draws it as a
  /// logo carries on drawing a logo. Only the splash passes anything else.
  ///
  /// Three things happen across that range and they overlap, because a stamp
  /// does not do them in turn: the outline draws, the ink arrives, the check
  /// strokes through.
  final double struck;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(struck)),
    );
  }
}

/// Maps a value onto a slice of the run, and eases it.
///
/// Written out rather than pulled from Interval + CurvedAnimation because the
/// painter is handed a number, not an animation, which keeps it drawable from
/// a test at any point in the sequence.
double _phase(double t, double from, double to, [Curve curve = Curves.easeOutCubic]) {
  if (t <= from) return 0;
  if (t >= to) return 1;
  // easeOutCubic by default: a stamp decelerates into the paper, it does not
  // arrive at constant speed.
  return curve.transform((t - from) / (to - from));
}

/// The distance along a closed path of its topmost point.
///
/// Sampled rather than derived, so it keeps working if the mark is ever redrawn
/// with different geometry. Sixty samples on an octagon is far more than
/// enough to land on the right vertex.
double _topOf(PathMetric metric) {
  var best = 0.0;
  var bestY = double.infinity;
  for (var i = 0; i <= 60; i += 1) {
    final at = metric.length * i / 60;
    final point = metric.getTangentForOffset(at)?.position;
    if (point != null && point.dy < bestY) {
      bestY = point.dy;
      best = at;
    }
  }
  return best;
}

/// A slice of a closed path that may run past its end and wrap.
Path _arc(PathMetric metric, double from, double to) {
  final length = metric.length;
  final out = Path();
  if (to - from >= length) return metric.extractPath(0, length);

  final a = from % length;
  final b = to % length;
  if (a <= b) {
    out.addPath(metric.extractPath(a, b), Offset.zero);
  } else {
    out.addPath(metric.extractPath(a, length), Offset.zero);
    out.addPath(metric.extractPath(0, b), Offset.zero);
  }
  return out;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.struck);

  final double struck;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final centre = Offset(s / 2, s / 2);
    final r = s / 2;

    final outline = _phase(struck, 0.00, 0.38);
    final ink = _phase(struck, 0.26, 0.56);
    // easeInOut rather than easeOut. Eased out, the check was finished by the
    // seventh tenth of the run and the rest of the sequence had a static shape
    // sitting in the middle of it.
    final check = _phase(struck, 0.50, 0.88, Curves.easeInOutCubic);

    // An octagon, drawn from its circumscribed circle so it stays regular at
    // any size.
    final seal = Path();
    for (var i = 0; i < 8; i += 1) {
      // Rotated an eighth of a turn so the mark sits on a flat edge rather
      // than balancing on a point.
      final angle = (i * 2 * pi / 8) - (pi / 8);
      final point = Offset(centre.dx + r * cos(angle), centre.dy + r * sin(angle));
      i == 0 ? seal.moveTo(point.dx, point.dy) : seal.lineTo(point.dx, point.dy);
    }
    seal.close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [TrustIqPalette.light.accent, TrustIqPalette.light.accentStrong],
      ).createShader(Offset.zero & size);

    if (ink > 0) {
      // A layer, because the alpha of a Paint does not reliably modulate a
      // shader fill. Drawing the gradient into a layer and compositing that at
      // the wanted opacity is the way to fade it that actually fades it.
      if (ink < 1) {
        canvas.saveLayer(
          Offset.zero & size,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: ink),
        );
        canvas.drawPath(seal, fill);
        canvas.restore();
      } else {
        canvas.drawPath(seal, fill);
      }
    }

    // The outline, traced. It leads the ink so the shape is legible before it
    // is filled: the edge of the stamp meets the paper first.
    //
    // Both ways from the top, not once around. Traced from the path's own
    // start point it began halfway down a side and chased around the shape,
    // which is the gesture of a progress ring rather than of a seal closing.
    if (outline > 0 && outline < 1) {
      for (final metric in seal.computeMetrics()) {
        final top = _topOf(metric);
        final reach = metric.length / 2 * outline;
        canvas.drawPath(
          _arc(metric, top - reach + metric.length, top + reach),
          Paint()
            ..shader = fill.shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.055
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // The check, drawn with a round join so it reads as one confident stroke
    // rather than two lines meeting.
    if (check > 0) {
      final tick = Path()
        ..moveTo(s * 0.30, s * 0.51)
        ..lineTo(s * 0.44, s * 0.65)
        ..lineTo(s * 0.71, s * 0.36);

      // Traced rather than faded. A check that appears all at once is a shape;
      // one that is drawn is somebody agreeing.
      final drawn = Path();
      for (final metric in tick.computeMetrics()) {
        drawn.addPath(metric.extractPath(0, metric.length * check), Offset.zero);
      }

      canvas.drawPath(
        drawn,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.095
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => oldDelegate.struck != struck;
}

/// The wordmark.
///
/// "Trust" in ink and "IQ" in the accent, because the product is a trust layer
/// first and the intelligence is what it uses, not what it sells. Tightened
/// tracking: at this size the default spacing reads as loose.
class TrustIqWordmark extends StatelessWidget {
  const TrustIqWordmark({super.key, this.fontSize = 30});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Trust'),
          TextSpan(text: 'IQ', style: TextStyle(color: c.accent)),
        ],
      ),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -fontSize * 0.032,
        color: c.ink,
        height: 1.1,
      ),
    );
  }
}

/// Mark and wordmark side by side, for the top of a screen rather than the
/// middle of one.
class TrustIqBar extends StatelessWidget {
  const TrustIqBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TrustIqMark(size: 26),
        const SizedBox(width: 10),
        TrustIqWordmark(fontSize: 17),
      ],
    );
  }
}

/// Mark and wordmark together, for a screen that has to introduce the product.
class TrustIqLockup extends StatelessWidget {
  const TrustIqLockup({super.key, this.markSize = 46, this.fontSize = 28, this.subtitle});

  final double markSize;
  final double fontSize;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        TrustIqMark(size: markSize),
        const SizedBox(height: Space.lg),
        TrustIqWordmark(fontSize: fontSize),
        if (subtitle != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: Type.small.copyWith(color: c.inkFaint),
          ),
        ],
      ],
    );
  }
}
