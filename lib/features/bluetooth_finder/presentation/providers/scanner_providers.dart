import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/scan_filter.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderFamily` is not part of the main Riverpod 3 barrel — family *types*
// live in `misc.dart`. Only needed to annotate the declaration below.
import 'package:flutter_riverpod/misc.dart';

/// The scan service is kept alive for the whole app lifetime, like
/// `adsServiceProvider`: it owns the platform subscription and the moving
/// average of every device seen. Disposing it between screens would restart the
/// averages and blank the list every time the user opens the radar.
final Provider<BluetoothScanService> bluetoothScanServiceProvider =
    Provider<BluetoothScanService>((Ref ref) {
      final BluetoothScanService service = BluetoothScanService();
      ref.onDispose(service.dispose);
      return service;
    });

/// Live device list, unfiltered. Kept alive alongside the service so a single
/// subscription feeds both the list and the radar screen.
final StreamProvider<List<DiscoveredDevice>> discoveredDevicesProvider =
    StreamProvider<List<DiscoveredDevice>>(
      (Ref ref) => ref.watch(bluetoothScanServiceProvider).devices,
    );

final StreamProvider<bool> isScanningProvider = StreamProvider<bool>(
  (Ref ref) => ref.watch(bluetoothScanServiceProvider).isScanning,
);

final StreamProvider<BluetoothAvailability> bluetoothAvailabilityProvider =
    StreamProvider<BluetoothAvailability>(
      (Ref ref) => ref.watch(bluetoothScanServiceProvider).availability,
    );

/// Devices actually shown, after the user's filters and sorted by signal.
final Provider<List<DiscoveredDevice>> visibleDevicesProvider =
    Provider<List<DiscoveredDevice>>((Ref ref) {
      final List<DiscoveredDevice> devices =
          ref.watch(discoveredDevicesProvider).value ??
          const <DiscoveredDevice>[];
      return ref.watch(scanFilterProvider).apply(devices);
    });

/// A single device by id, straight from the live stream.
///
/// The radar screen watches this instead of receiving a device object through
/// the route: the reading has to keep updating while the screen is open, and a
/// value captured at push time would be frozen.
final ProviderFamily<DiscoveredDevice?, String> deviceByIdProvider =
    Provider.family<DiscoveredDevice?, String>((Ref ref, String id) {
      final List<DiscoveredDevice> devices =
          ref.watch(discoveredDevicesProvider).value ??
          const <DiscoveredDevice>[];
      for (final DiscoveredDevice device in devices) {
        if (device.id == id) return device;
      }
      return null;
    }, isAutoDispose: true);

final NotifierProvider<ScanFilterController, ScanFilter> scanFilterProvider =
    NotifierProvider<ScanFilterController, ScanFilter>(
      ScanFilterController.new,
    );

/// Persists the two list filters so the user does not re-tick them on every
/// launch. Written through `KeyValueStore`, which is already loaded before the
/// first frame.
class ScanFilterController extends Notifier<ScanFilter> {
  static const String _hideUnidentifiedKey = 'finder_hide_unidentified';
  static const String _hideWeakKey = 'finder_hide_weak_signal';

  @override
  ScanFilter build() {
    final store = ref.watch(keyValueStoreProvider);
    return ScanFilter(
      hideUnidentified: store.getBool(_hideUnidentifiedKey, fallback: true),
      hideWeakSignal: store.getBool(_hideWeakKey, fallback: true),
    );
  }

  Future<void> setHideUnidentified({required bool value}) async {
    state = state.copyWith(hideUnidentified: value);
    await ref
        .read(keyValueStoreProvider)
        .setBool(_hideUnidentifiedKey, value: value);
  }

  Future<void> setHideWeakSignal({required bool value}) async {
    state = state.copyWith(hideWeakSignal: value);
    await ref.read(keyValueStoreProvider).setBool(_hideWeakKey, value: value);
  }
}
