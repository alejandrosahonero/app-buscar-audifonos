import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A pinned device, live or not.
///
/// It watches the scan stream by id instead of being handed a device, so it
/// lights up the moment its earbud starts advertising and greys out again when
/// it stops — without the surrounding list having to rebuild.
///
/// The saved description is the fallback, not the label: a live advertisement
/// wins field by field, because it may carry a battery level or a name the
/// snapshot never had — while the snapshot still covers the first anonymous
/// packets of a new scan, which is when the row would otherwise blink to
/// "Bluetooth device".
class FavoriteDeviceTile extends ConsumerWidget {
  const FavoriteDeviceTile({
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final FavoriteDevice favorite;
  final VoidCallback onTap;

  /// Unpinning. Long press rather than a button on the row: removing is rare
  /// and a destructive control sitting next to the row's own tap target is how
  /// people lose a favourite by accident.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DiscoveredDevice? live = ref.watch(deviceByIdProvider(favorite.id));
    final DeviceIdentity identity = live == null
        ? favorite.identity
        : favorite.identity.mergedWith(live.identity);

    return DeviceTile(
      identity: identity,
      device: live,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
