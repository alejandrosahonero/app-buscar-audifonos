import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_identity_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// One row of the scan results.
///
/// Its own widget rather than a `_buildTile()` method so a signal update only
/// repaints the tile that changed, not the whole list.
///
/// Three layers of information, in the order a person reads them: what it is
/// (icon + name), what kind of thing it is (kind + brand), and the details
/// worth acting on (battery, already paired, pairing protocols). The device
/// address is deliberately absent — see [DiscoveredDevice.id].
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    required this.identity,
    required this.onTap,
    this.device,
    this.onLongPress,
    this.customName,
    super.key,
  });

  /// What to call this device. Passed in rather than read from [device] because
  /// a favourite that is out of range still has a name — its saved one.
  final DeviceIdentity identity;

  /// The live reading, or `null` when nothing is being heard from this device
  /// right now. Only favourites ever reach that state: the scan list is built
  /// out of what the phone can hear.
  final DiscoveredDevice? device;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The name the user gave this device, if they gave it one. Only favourites
  /// can have one — see [FavoriteDevice.customName].
  final String? customName;

  @override
  Widget build(BuildContext context) {
    final DiscoveredDevice? device = this.device;
    final String? summary = deviceSummaryLine(context, identity);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        // Everything on the row shares one centre line. `ListTile` cannot do
        // this: it positions the title and the subtitle from their text
        // baselines against fixed offsets, which is what was pushing the name
        // upwards and what forced the empty reserved lines — a row is not a
        // fixed number of lines here, it is however much this device has to
        // say.
        child: Row(
          children: <Widget>[
            DeviceAvatar(
              category: identity.category,
              band: device?.band ?? ProximityBand.far,
              // A proximity tint on a device we cannot hear would be a reading
              // we do not have. Out of range is grey, not "far away".
              color: device == null ? context.colors.outline : null,
              // Carries the "no signal" state on its own, which is why the row
              // no longer spends a chip on saying it.
              offline: device == null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    deviceDisplayName(
                      context,
                      identity,
                      customName: customName,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Only when the advertisement actually named a kind or a
                  // brand. Nothing is reserved for it: with no brand to show,
                  // the chips sit straight under the name.
                  if (summary != null)
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  // Same rule, and the gap travels with them: battery, traits
                  // and "paired" all describe a packet, so a device that is not
                  // being heard has none and gives the space back.
                  if (device != null)
                    DeviceMetaChips(
                      identity: identity,
                      isPaired: device.isPaired,
                      // Two, not three: a third chip wraps to a second line on
                      // a narrow phone, and that line would be the one row in
                      // the list that is taller than the rest.
                      maxChips: 2,
                      gapAbove: AppSpacing.xs,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (device != null) ...<Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${device.closenessPercent} %',
                    style: context.texts.titleMedium?.copyWith(
                      color: proximityColor(context, device.band),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SignalStrengthIcon(closeness: device.closeness),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(Icons.chevron_right, color: context.colors.outline),
          ],
        ),
      ),
    );
  }
}
