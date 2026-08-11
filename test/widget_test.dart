import 'dart:async';

import 'package:buscar_audifonos/app.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/billing/premium_state.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replaces the real controller so the test never touches Google Play Billing.
/// Overriding `build` is enough: no platform channel is opened.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: false, storeAvailable: false);
}

/// Stands in for the real scanner so the test never touches the Bluetooth
/// stack. `implements` (not `extends`) on purpose: the real constructor
/// subscribes to a platform stream.
class _FakeScanService implements BluetoothScanService {
  _FakeScanService({this.seen = const <DiscoveredDevice>[]});

  final List<DiscoveredDevice> seen;
  bool scanning = false;

  @override
  Stream<List<DiscoveredDevice>> get devices =>
      Stream<List<DiscoveredDevice>>.value(seen);

  @override
  List<DiscoveredDevice> get latestDevices => seen;

  @override
  Stream<bool> get isScanning => Stream<bool>.value(scanning);

  @override
  bool get isScanningNow => scanning;

  @override
  Stream<BluetoothAvailability> get availability =>
      Stream<BluetoothAvailability>.value(BluetoothAvailability.ready);

  @override
  Future<Set<String>> bondedDeviceIds() async => const <String>{};

  @override
  Future<void> start() async => scanning = true;

  @override
  Future<void> stop() async => scanning = false;

  @override
  Future<void> requestEnable() async {}

  @override
  Future<void> dispose() async {}
}

DiscoveredDevice _device({
  required String id,
  required String name,
  required int rssi,
}) => DiscoveredDevice.firstSeen(
  id: id,
  name: name,
  rssi: rssi,
  lastSeen: DateTime(2026),
);

Future<void> _pumpApp(
  WidgetTester tester, {
  required BluetoothScanService scanService,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        premiumControllerProvider.overrideWith(_FakePremiumController.new),
        bluetoothScanServiceProvider.overrideWithValue(scanService),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the scanner screen invites the user to start a scan', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, scanService: _FakeScanService());

    expect(find.text('Buscar Audífonos: Localizador'), findsOneWidget);
    expect(find.text('No devices in sight'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('discovered devices are listed strongest first', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      scanService: _FakeScanService(
        seen: <DiscoveredDevice>[
          _device(id: 'AA:BB:CC:DD:EE:01', name: 'Far buds', rssi: -80),
          _device(id: 'AA:BB:CC:DD:EE:02', name: 'Near buds', rssi: -45),
        ],
      ),
    );

    final Iterable<String> titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((ListTile tile) => (tile.title! as Text).data!);

    expect(titles, <String>['Near buds', 'Far buds']);
  });

  testWidgets('the default filters hide unnamed and very weak devices', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      scanService: _FakeScanService(
        seen: <DiscoveredDevice>[
          _device(id: 'AA:BB:CC:DD:EE:01', name: 'Good buds', rssi: -50),
          _device(id: 'AA:BB:CC:DD:EE:02', name: '', rssi: -50),
          _device(id: 'AA:BB:CC:DD:EE:03', name: 'Way too far', rssi: -99),
        ],
      ),
    );

    expect(find.text('Good buds'), findsOneWidget);
    expect(find.text('Unnamed device'), findsNothing);
    expect(find.text('Way too far'), findsNothing);
    expect(find.text('2 hidden'), findsOneWidget);
  });
}
