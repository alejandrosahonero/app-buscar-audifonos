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

  @override
  Widget build(BuildContext context) {
    final DiscoveredDevice? device = this.device;
    final String? summary = deviceSummaryLine(context, identity);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      isThreeLine: true,
      leading: DeviceAvatar(
        category: identity.category,
        band: device?.band ?? ProximityBand.far,
        // A proximity tint on a device we cannot hear would be a reading we do
        // not have. Out of range is grey, not "far away".
        color: device == null ? context.colors.outline : null,
      ),
      title: Text(
        deviceDisplayName(context, identity),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (summary != null)
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          if (device == null)
            DeviceMetaChip(
              icon: Icons.bluetooth_disabled,
              label: context.l10n.finderFavoriteOffline,
            )
          else
            DeviceMetaChips(identity: identity, isPaired: device.isPaired),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (device != null)
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
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
