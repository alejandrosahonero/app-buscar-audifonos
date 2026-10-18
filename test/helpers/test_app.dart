import 'dart:async';

import 'package:buscar_audifonos/app.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/location_services.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/billing/premium_state.dart';
import 'package:buscar_audifonos/services/permissions/permission_providers.dart';
import 'package:buscar_audifonos/services/permissions/permission_service.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test doubles shared by the widget and golden tests: the app pumped with no
/// Bluetooth stack, no billing and every permission granted.

/// Replaces the real controller so the test never touches Google Play Billing.
/// Overriding `build` is enough: no platform channel is opened.
class FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: false, storeAvailable: false);
}

/// Stands in for the real scanner so the test never touches the Bluetooth
/// stack. `implements` (not `extends`) on purpose: the real constructor
/// subscribes to a platform stream.
class FakeScanService implements BluetoothScanService {
  FakeScanService({this.seen = const <DiscoveredDevice>[]});

  final List<DiscoveredDevice> seen;
  bool scanning = false;

  @override
  Stream<List<DiscoveredDevice>> get devices =>
      Stream<List<DiscoveredDevice>>.value(seen);

  @override
  List<DiscoveredDevice> get latestDevices => seen;

  final StreamController<bool> _scanning = StreamController<bool>.broadcast();

  /// Replays the current value then follows the changes, like the plugin's own
  /// stream: a one-shot `Stream.value` would never tell the UI that a scan
  /// started.
  @override
  Stream<bool> get isScanning async* {
    yield scanning;
    yield* _scanning.stream;
  }

  @override
  bool get isScanningNow => scanning;

  @override
  Stream<BluetoothAvailability> get availability =>
      Stream<BluetoothAvailability>.value(BluetoothAvailability.ready);

  @override
  Future<Set<String>> bondedDeviceIds() async => const <String>{};

  @override
  Future<void> start() async {
    scanning = true;
    _scanning.add(true);
  }

  @override
  Future<void> stop() async {
    scanning = false;
    _scanning.add(false);
  }

  String? focusedId;

  @override
  void focusOn(String? deviceId) => focusedId = deviceId;

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<void> dispose() async => _scanning.close();
}

/// Grants everything without touching `permission_handler`, whose platform
/// channel never answers on the test host — the real service would hang the
/// permission flow instead of denying it.
class FakePermissionService implements PermissionService {
  @override
  Future<PermissionOutcome> check(AppPermission permission) async =>
      PermissionOutcome.granted;

  @override
  Future<PermissionOutcome> request(AppPermission permission) async =>
      PermissionOutcome.granted;

  @override
  Future<Map<AppPermission, PermissionOutcome>> requestAll(
    List<AppPermission> permissions,
  ) async => <AppPermission, PermissionOutcome>{
    for (final AppPermission permission in permissions)
      permission: PermissionOutcome.granted,
  };

  @override
  Future<bool> shouldShowRationale(AppPermission permission) async => false;

  @override
  Future<bool> openSettings() async => false;
}

/// Location always on: the native channel does not exist on the test host.
class FakeLocationServices implements LocationServices {
  bool off = false;

  @override
  Future<bool> blocksScan() async => off;

  @override
  Future<bool> openSettings() async => false;
}

Future<void> pumpApp(
  WidgetTester tester, {
  required BluetoothScanService scanService,
  Map<String, Object> preferences = const <String, Object>{},
  bool settle = true,
  LocationServices? locationServices,
}) async {
  // The first-run welcome is covered by its own test; everything else starts
  // past it, like every launch after the first.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'welcome_done': true,
    ...preferences,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        premiumControllerProvider.overrideWith(FakePremiumController.new),
        bluetoothScanServiceProvider.overrideWithValue(scanService),
        permissionServiceProvider.overrideWithValue(FakePermissionService()),
        locationServicesProvider.overrideWithValue(
          locationServices ?? FakeLocationServices(),
        ),
      ],
      child: const App(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
