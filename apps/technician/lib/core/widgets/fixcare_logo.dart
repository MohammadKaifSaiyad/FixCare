import 'package:flutter/material.dart';

import '../theme.dart';

/// The FixCare wrench-and-check-badge monogram, drawn from the design file's
/// SVG geometry (viewBox 0 0 48 48). No SVG dependency — a CustomPainter
/// reproduces the exact paths.
///
/// The green check badge (#1D6B4F) and its white tick are fixed brand elements;
/// only the wrench recolors (terracotta on light backgrounds, white on colored)
/// via [wrenchColor].
class FixCareLogoMark extends StatelessWidget {
  const FixCareLogoMark({super.key, this.size = 52, this.wrenchColor = FixCareColors.primary});

  final double size;
  final Color wrenchColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(wrenchColor)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.wrenchColor);
  final Color wrenchColor;

  @override
  void paint(Canvas canvas, Size size) {
    // The path data is authored in a 48x48 viewBox; scale to the requested size.
    final s = size.width / 48.0;
    canvas.scale(s, s);

    // Wrench silhouette (solid fill).
    final wrench = Path()
      ..moveTo(30.5, 8.5)
      ..relativeArcToPoint(const Offset(-10.2, 9.9), radius: const Radius.circular(8), largeArc: false, clockwise: false)
      ..lineTo(8.8, 29.9)
      ..relativeArcToPoint(const Offset(0, 4.5), radius: const Radius.circular(3.2), largeArc: false, clockwise: false)
      ..lineTo(9.6, 35.2)
      ..relativeArcToPoint(const Offset(4.5, 0), radius: const Radius.circular(3.2), largeArc: false, clockwise: false)
      ..lineTo(25.6, 23.7)
      ..relativeArcToPoint(const Offset(9.9, -10.7), radius: const Radius.circular(8), largeArc: false, clockwise: false)
      ..lineTo(31.3, 17.2)
      ..lineTo(27.8, 16.3)
      ..lineTo(26.9, 12.8)
      ..lineTo(31.1, 8.6)
      ..relativeArcToPoint(const Offset(-0.6, -0.1), radius: const Radius.circular(8), largeArc: false, clockwise: false)
      ..close();
    canvas.drawPath(wrench, Paint()..color = wrenchColor..style = PaintingStyle.fill);

    // Check badge circle (fixed success green).
    canvas.drawCircle(const Offset(34, 34), 10, Paint()..color = FixCareColors.success);

    // Checkmark tick (white stroke, round caps).
    final tick = Path()
      ..moveTo(29.5, 34.2)
      ..lineTo(32.5, 37.2)
      ..lineTo(38.5, 30.8);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.wrenchColor != wrenchColor;
}

/// The white rounded-square app-icon lockup (splash). 88px square by default,
/// holding the primary-colored mark on white.
class FixCareLogoTile extends StatelessWidget {
  const FixCareLogoTile({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.32), // ~28px at 88
        boxShadow: const [
          BoxShadow(color: Color(0x2E241A15), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      alignment: Alignment.center,
      child: FixCareLogoMark(size: size * 0.59), // ~52 at 88
    );
  }
}

/// Horizontal mark + "FixCare" wordmark lockup, for colored/dark backgrounds.
class FixCareWordmark extends StatelessWidget {
  const FixCareWordmark({super.key, this.color = Colors.white, this.markSize = 26});

  final Color color;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FixCareLogoMark(size: markSize, wrenchColor: color),
        const SizedBox(width: 9),
        Text(
          'FixCare',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -0.32,
          ),
        ),
      ],
    );
  }
}
