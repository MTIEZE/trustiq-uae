import 'dart:math';

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
class TrustIqMark extends StatelessWidget {
  const TrustIqMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final r = s / 2;

    // An octagon, drawn from its circumscribed circle so it stays regular at
    // any size.
    final seal = Path();
    for (var i = 0; i < 8; i += 1) {
      // Rotated an eighth of a turn so the mark sits on a flat edge rather
      // than balancing on a point.
      final angle = (i * 2 * pi / 8) - (pi / 8);
      final point = Offset(c.dx + r * cos(angle), c.dy + r * sin(angle));
      i == 0 ? seal.moveTo(point.dx, point.dy) : seal.lineTo(point.dx, point.dy);
    }
    seal.close();

    canvas.drawPath(
      seal,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TrustIqColors.accent, TrustIqColors.accentStrong],
        ).createShader(Offset.zero & size),
    );

    // The check, drawn with a round join so it reads as one confident stroke
    // rather than two lines meeting.
    final tick = Path()
      ..moveTo(s * 0.30, s * 0.51)
      ..lineTo(s * 0.44, s * 0.65)
      ..lineTo(s * 0.71, s * 0.36);

    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.095
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
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
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Trust'),
          TextSpan(text: 'IQ', style: const TextStyle(color: TrustIqColors.accent)),
        ],
      ),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -fontSize * 0.032,
        color: TrustIqColors.ink,
        height: 1.1,
      ),
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
            style: Type.small.copyWith(color: TrustIqColors.inkFaint),
          ),
        ],
      ],
    );
  }
}
