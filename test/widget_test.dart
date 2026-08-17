import 'dart:async';
import 'dart:convert';

import 'package:buscar_audifonos/app.dart';
import 'package:buscar_audifonos/core/widgets/adaptive_banner_ad.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
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
  // A bare advertised name is all these list tests need: an empty one is
  // exactly the "we could not identify this at all" case the filter drops.
  identity: DeviceIdentity(advertisedName: name),
  rssi: rssi,
  lastSeen: DateTime(2026),
);

/// Builds the stored form of the favourites list, exactly as
/// `FavoriteDevicesController` writes it.
String _storedFavorites(List<({String id, String name})> favorites) {
  return jsonEncode(<Map<String, Object?>>[
    for (final ({String id, String name}) favorite in favorites)
      FavoriteDevice(
        id: favorite.id,
        identity: DeviceIdentity(advertisedName: favorite.name),
      ).toJson(),
  ]);
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required BluetoothScanService scanService,
  Map<String, Object> preferences = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
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

  testWidgets('the stored language wins over the phone language', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      scanService: _FakeScanService(),
      preferences: <String, Object>{'app_locale': 'es'},
    );

    // Same screen the other tests read in English.
    expect(find.text('Escanear'), findsOneWidget);
    expect(find.text('Ningún dispositivo a la vista'), findsOneWidget);
    expect(find.text('Scan'), findsNothing);
  });

  testWidgets('settings switches the language without a restart', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, scanService: _FakeScanService());

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Each language names itself, so these two read the same in every locale.
    expect(find.text('Español'), findsOneWidget);
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Idioma'), findsOneWidget);
  });

  testWidgets('the scan hint points at the button only while idle', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, scanService: _FakeScanService());

    expect(find.text('Tap the Scan button to start looking'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });

  testWidgets('the scan hint disappears once a scan is running', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, scanService: _FakeScanService()..scanning = true);

    expect(find.text('Tap the Scan button to start looking'), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });

  testWidgets('the scan button is laid out clear of the banner slot', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, scanService: _FakeScanService());

    // The banner travels in the scaffold's bottom bar, not in the body: that is
    // what makes the scaffold position the floating button above it instead of
    // on top of it.
    final Scaffold scaffold = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(scaffold.bottomNavigationBar, isA<AdaptiveBannerAd>());
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(AdaptiveBannerAd),
      ),
      findsNothing,
    );
  });

  testWidgets('a favourite that is out of range is still listed, as offline', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      scanService: _FakeScanService(
        seen: <DiscoveredDevice>[
          _device(id: 'AA:BB:CC:DD:EE:01', name: 'Some speaker', rssi: -50),
        ],
      ),
      preferences: <String, Object>{
        'finder_favorite_devices': _storedFavorites(
          <({String id, String name})>[
            (id: 'AA:BB:CC:DD:EE:09', name: 'Lost buds'),
          ],
        ),
      },
    );

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Other devices'), findsOneWidget);
    expect(find.text('Lost buds'), findsOneWidget);
    expect(find.text('No signal'), findsOneWidget);
  });

  testWidgets('a favourite that is in range is pinned on top, and only once', (
    WidgetTester tester,
  ) async {
    await _pumpApp(
      tester,
      scanService: _FakeScanService(
        seen: <DiscoveredDevice>[
          // Stronger signal, yet it must still sort below the favourite.
          _device(id: 'AA:BB:CC:DD:EE:01', name: 'Near speaker', rssi: -40),
          _device(id: 'AA:BB:CC:DD:EE:09', name: 'My buds', rssi: -70),
        ],
      ),
      preferences: <String, Object>{
        'finder_favorite_devices': _storedFavorites(
          <({String id, String name})>[
            (id: 'AA:BB:CC:DD:EE:09', name: 'My buds'),
          ],
        ),
      },
    );

    final Iterable<String> titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((ListTile tile) => (tile.title! as Text).data!);

    expect(titles, <String>['My buds', 'Near speaker']);
    expect(find.text('No signal'), findsNothing);
  });
}
