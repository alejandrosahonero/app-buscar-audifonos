import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:flutter/material.dart';

/// Maps a proximity band to the app's semantic palette.
///
/// Single source of truth for "red = far, amber = near, green = very near", so
/// the list icon and the radar can never drift apart.
Color proximityColor(BuildContext context, ProximityBand band) =>
    switch (band) {
      ProximityBand.far => context.colors.error,
      ProximityBand.near => context.semanticColors.warning,
      ProximityBand.veryNear => context.semanticColors.success,
    };

String proximityLabel(BuildContext context, ProximityBand band) =>
    switch (band) {
      ProximityBand.far => context.l10n.radarBandFar,
      ProximityBand.near => context.l10n.radarBandNear,
      ProximityBand.veryNear => context.l10n.radarBandVeryNear,
    };

/// Four-step signal bars, coloured by band.
class SignalStrengthIcon extends StatelessWidget {
  const SignalStrengthIcon({required this.closeness, super.key});

  /// 0..1, already smoothed.
  final double closeness;

  @override
  Widget build(BuildContext context) {
    final ProximityBand band = Proximity.bandFor(closeness);
    final Color color = proximityColor(context, band);
    // 1..4 bars: an empty icon reads as "broken" rather than "far".
    final int bars = (closeness * 4).ceil().clamp(1, 4);

    return SizedBox(
      width: 24,
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (int index = 1; index <= 4; index++)
            _Bar(
              height: 6.0 * index,
              color: index <= bars ? color : context.colors.outlineVariant,
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}
