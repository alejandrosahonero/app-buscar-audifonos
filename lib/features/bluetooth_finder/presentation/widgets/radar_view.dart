import 'dart:math' as math;

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// The animated proximity radar.
///
/// Reads as a radar screen — concentric rings plus a rotating sweep — but the
/// blip is *not* a bearing: BLE gives no direction, only strength. The blip
/// therefore sits on a ring whose radius shrinks as the signal grows, so the
/// user hill-climbs by walking and watching the ring close in.
///
/// [closeness] is animated with an implicit tween instead of being painted
/// raw: RSSI arrives in steps and an un-tweened radar looks like it is
/// glitching rather than measuring.
class RadarView extends StatefulWidget {
  const RadarView({required this.closeness, required this.active, super.key});

  /// 0..1, already smoothed by [Proximity.smooth].
  final double closeness;

  /// False when the device stopped advertising: the sweep freezes and the
  /// colours desaturate so a stale reading is never mistaken for a live one.
  final bool active;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _sweep.repeat();
  }

  @override
  void didUpdateWidget(RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    // Stopping the controller when the signal is lost also stops the ticker,
    // which is what keeps a stale radar from burning battery in the user's hand.
    if (widget.active) {
      _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProximityBand band = Proximity.bandFor(widget.closeness);
    final Color color = widget.active
        ? proximityColor(context, band)
        : context.colors.outline;

    return AspectRatio(
      aspectRatio: 1,
      // The radar repaints on every animation frame; the boundary stops that
      // from dirtying the labels and buttons around it.
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: widget.closeness),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (BuildContext context, double closeness, Widget? child) {
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: const Duration(milliseconds: 450),
              builder:
                  (BuildContext context, Color? tweenedColor, Widget? child) {
                    return CustomPaint(
                      painter: _RadarPainter(
                        closeness: closeness,
                        color: tweenedColor ?? color,
                        gridColor: context.colors.outlineVariant,
                        sweep: _sweep,
                        active: widget.active,
                      ),
                      child: child,
                    );
                  },
              child: child,
            );
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _RadarReadout(
                closeness: widget.closeness,
                active: widget.active,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarReadout extends StatelessWidget {
  const _RadarReadout({required this.closeness, required this.active});

  final double closeness;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ProximityBand band = Proximity.bandFor(closeness);
    final Color color = active
        ? proximityColor(context, band)
        : context.colors.outline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${(closeness * 100).round()}%',
          style: context.texts.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          active
              ? proximityLabel(context, band)
              : context.l10n.radarSignalLostTitle,
          textAlign: TextAlign.center,
          style: context.texts.labelLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.closeness,
    required this.color,
    required this.gridColor,
    required this.sweep,
    required this.active,
  }) : super(repaint: sweep);

  final double closeness;
  final Color color;
  final Color gridColor;
  final Animation<double> sweep;
  final bool active;

  static const int _ringCount = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;

    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;

    for (int ring = 1; ring <= _ringCount; ring++) {
      canvas.drawCircle(center, radius * ring / _ringCount, grid);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      grid,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      grid,
    );

    if (active) _paintSweep(canvas, center, radius);
    _paintProximityRing(canvas, center, radius);
  }

  /// Rotating wedge, drawn as a fading gradient so it reads as a sweep rather
  /// than a spinning pie slice.
  void _paintSweep(Canvas canvas, Offset center, double radius) {
    final double angle = sweep.value * 2 * math.pi;
    final Rect bounds = Rect.fromCircle(center: center, radius: radius);

    final Paint wedge = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2,
        colors: <Color>[
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.35),
        ],
        transform: GradientRotation(angle - math.pi / 2),
      ).createShader(bounds);

    canvas.drawArc(bounds, angle - math.pi / 2, math.pi / 2, true, wedge);
  }

  /// The blip ring: radius collapses towards the centre as the signal grows.
  void _paintProximityRing(Canvas canvas, Offset center, double radius) {
    final double blipRadius = radius * (1 - closeness).clamp(0.06, 1.0);

    canvas.drawCircle(
      center,
      blipRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      center,
      blipRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.closeness != closeness ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.active != active;
}
