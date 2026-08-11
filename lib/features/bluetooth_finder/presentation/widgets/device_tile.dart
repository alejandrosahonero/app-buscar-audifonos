import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// One row of the scan results.
///
/// Its own widget rather than a `_buildTile()` method so a signal update only
/// repaints the tile that changed, not the whole list.
class DeviceTile extends StatelessWidget {
  const DeviceTile({required this.device, required this.onTap, super.key});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SignalStrengthIcon(closeness: device.closeness),
      title: Text(
        device.hasName ? device.name : context.l10n.finderUnnamedDevice,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: device.hasName
            ? null
            : context.texts.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: context.colors.onSurfaceVariant,
              ),
      ),
      subtitle: Text(
        // MAC / UUID plus the raw reading: two identical earbuds are only
        // distinguishable by their address.
        '${device.id}  ·  ${device.rssi} dBm',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${device.closenessPercent} %',
            style: context.texts.titleMedium?.copyWith(
              color: proximityColor(context, device.band),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
