import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
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
  const DeviceTile({required this.device, required this.onTap, super.key});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? summary = deviceSummaryLine(context, device.identity);

    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: DeviceAvatar(
        category: device.identity.category,
        band: device.band,
      ),
      title: Text(
        deviceDisplayName(context, device.identity),
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
          DeviceMetaChips(identity: device.identity, isPaired: device.isPaired),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
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
