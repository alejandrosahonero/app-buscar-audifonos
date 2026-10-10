import 'dart:math' as math;

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// The proximity beam: a lighthouse at the bottom of the screen whose light
/// reaches further, and burns brighter, the closer the device is.
///
/// The swing of the beam is atmosphere, **not** a bearing: BLE gives strength,
/// never direction. What the user steers by is how far the light reaches, and
/// the number above it. That is why the beam never points anywhere on purpose.
///
/// [closeness] is tweened: RSSI arrives in steps, and a light that jumps
/// between lengths reads as a glitch rather than a measurement.
class RadarView extends StatefulWidget {
  const RadarView({required this.closeness, required this.active, super.key});

  /// 0..1, already smoothed by [Proximity.smooth].
  final double closeness;

  /// False while nothing is being heard: the light goes out and the swing
  /// stops, so a stale reading is never mistaken for a live one.
  final bool active;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swing = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSwing();
  }

  @override
  void didUpdateWidget(RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSwing();
  }

  /// Stopping the controller also stops the ticker, which is what keeps an
  /// idle beam from burning battery in the user's hand.
  void _syncSwing() {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.active && !reduceMotion) {
      if (!_swing.isAnimating) _swing.repeat();
    } else {
      _swing.stop();
    }
  }

  @override
  void dispose() {
    _swing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? proximityColor(context, Proximity.bandFor(widget.closeness))
        : context.colors.outline;

    // Repaints on every animation frame; the boundary keeps that from
    // dirtying the number and the buttons around it.
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: widget.active ? widget.closeness : 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (BuildContext context, double closeness, Widget? child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _BeamPainter(
              closeness: closeness,
              color: color,
              gridColor: context.colors.outlineVariant,
              swing: _swing,
              active: widget.active,
            ),
          );
        },
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({
    required this.closeness,
    required this.color,
    required this.gridColor,
    required this.swing,
    required this.active,
  }) : super(repaint: swing);

  final double closeness;
  final Color color;
  final Color gridColor;
  final Animation<double> swing;
  final bool active;

  static const int _arcCount = 3;

  /// Half the opening of the beam, and how far it swings to either side.
  static const double _halfWidth = 0.3;
  static const double _swingAmplitude = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset source = Offset(size.width / 2, size.height - 14);
    final double reach = math.min(size.height - 20, size.width * 0.95);

    // Distance marks: half-rings around the lighthouse. Where the light ends
    // against them is the reading.
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;
    for (int arc = 1; arc <= _arcCount; arc++) {
      final double r = reach * arc / _arcCount;
      canvas.drawArc(
        Rect.fromCircle(center: source, radius: r),
        math.pi,
        math.pi,
        false,
        grid,
      );
    }

    if (active) {
      final double length = reach * (0.25 + 0.75 * closeness);
      final double heading =
          -math.pi / 2 + math.sin(swing.value * 2 * math.pi) * _swingAmplitude;
      final Rect bounds = Rect.fromCircle(center: source, radius: length);

      final Paint beam = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: 0.35 + 0.4 * closeness),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds);
      canvas.drawArc(bounds, heading - _halfWidth, _halfWidth * 2, true, beam);

      canvas.drawCircle(
        source,
        14,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    canvas.drawCircle(source, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BeamPainter oldDelegate) =>
      oldDelegate.closeness != closeness ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.active != active;
}
