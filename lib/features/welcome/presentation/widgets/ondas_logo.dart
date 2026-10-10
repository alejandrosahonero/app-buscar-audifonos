import 'dart:math' as math;

import 'package:buscar_audifonos/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The "Ondas" mark, painted rather than loaded: it is a handful of arcs and
/// one SVG dependency would cost more than this file.
///
/// Same geometry as `brand/logo.svg` — a 108-unit canvas, art scaled into the
/// central safe circle — so the logo on the welcome screen is the launcher
/// icon the user just tapped.
class OndasLogo extends StatelessWidget {
  const OndasLogo({this.size = 160, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: const _OndasPainter(),
      ),
    );
  }
}

class _OndasPainter extends CustomPainter {
  const _OndasPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 108)
      ..translate(54, 54)
      ..scale(0.82)
      ..translate(-54, -55.5);

    void arc(double radius, double width, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(54, 64), radius: radius),
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    arc(28, 5.5, AppColors.espuma);
    arc(18, 4.5, AppColors.espuma.withValues(alpha: 0.55));
    arc(9, 4.5, AppColors.luz);

    final Paint cup = Paint()..color = AppColors.espuma;
    for (final double left in <double>[20, 76]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 60, 12, 18),
          const Radius.circular(5),
        ),
        cup,
      );
    }
    canvas.drawCircle(
      const Offset(54, 66),
      4.5,
      Paint()..color = AppColors.luz,
    );
  }

  @override
  bool shouldRepaint(_OndasPainter oldDelegate) => false;
}
