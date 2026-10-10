import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_identity_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// Every device the scan hears, placed on one line from far to very close.
///
/// The list answers "what is around me"; this answers "which one is getting
/// closer" at a glance, without reading numbers. Only the closest is named:
/// labels for every dot would collide on a narrow phone, and the closest is
/// the one the user is about to open.
class ProximityScale extends StatelessWidget {
  const ProximityScale({required this.devices, super.key});

  /// Visible devices, already filtered. Order does not matter.
  final List<DiscoveredDevice> devices;

  /// Dots beyond this add noise, not information.
  static const int _maxDots = 8;
  static const double _dot = 10;

  @override
  Widget build(BuildContext context) {
    final List<DiscoveredDevice> shown =
        (List<DiscoveredDevice>.of(devices)
              ..sort((a, b) => b.closeness.compareTo(a.closeness)))
            .take(_maxDots)
            .toList();
    final DiscoveredDevice? closest = shown.isEmpty ? null : shown.first;
    final TextStyle? axis = context.texts.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
      letterSpacing: 0.8,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(context.l10n.radarBandFar.toUpperCase(), style: axis),
              Text(context.l10n.radarBandVeryNear.toUpperCase(), style: axis),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 46,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double usable = constraints.maxWidth - _dot;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.sm),
                    ),
                    gradient: LinearGradient(
                      colors: <Color>[
                        context.colors.primary.withValues(alpha: 0),
                        context.colors.primary.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Farthest first, so the closest is painted on top.
                      for (final DiscoveredDevice device in shown.reversed)
                        Positioned(
                          left: usable * device.closeness,
                          top: 28 - _dot / 2,
                          child: _Dot(
                            color: proximityColor(context, device.band),
                            ringed: identical(device, closest),
                          ),
                        ),
                      if (closest != null)
                        Positioned(
                          top: 4,
                          left: 0,
                          right: 0,
                          child: Align(
                            alignment: Alignment(
                              (closest.closeness * 2 - 1).clamp(-1.0, 1.0),
                              0,
                            ),
                            child: Text(
                              deviceDisplayName(context, closest.identity),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.finderScaleHint,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.ringed});

  final Color color;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ProximityScale._dot,
      height: ProximityScale._dot,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: ringed
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  spreadRadius: 5,
                ),
              ]
            : null,
      ),
    );
  }
}
