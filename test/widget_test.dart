import 'dart:async';
import 'dart:convert';

import 'package:buscar_audifonos/app.dart';
import 'package:buscar_audifonos/core/widgets/adaptive_banner_ad.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/screens/radar_screen.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/billing/premium_state.dart';
import 'package:buscar_audifonos/services/permissions/permission_providers.dart';
import 'package:buscar_audifonos/services/permissions/permission_service.dart';
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

  @override
  Future<void> requestEnable() async {}

  @override
  Future<void> dispose() async => _scanning.close();
}

/// Grants everything without touching `permission_handler`, whose platform
/// channel never answers on the test host — the real service would hang the
/// permission flow instead of denying it.
class _FakePermissionService implements PermissionService {
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
        permissionServiceProvider.overrideWithValue(_FakePermissionService()),
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
    expect(find.text('Tap "Scan" to look for devices'), findsOneWidget);
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
    expect(
      find.text('Pulsa "Escanear" para buscar dispositivos'),
      findsOneWidget,
    );
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

  testWidgets('a stopped scan offers renaming a favourite, a running one does '
      'not', (WidgetTester tester) async {
    final _FakeScanService service = _FakeScanService(
      seen: <DiscoveredDevice>[
        _device(id: 'AA:BB:CC:DD:EE:09', name: 'LE_WH-1000XM4', rssi: -55),
      ],
    );
    await _pumpApp(
      tester,
      scanService: service,
      preferences: <String, Object>{
        'finder_favorite_devices': _storedFavorites(
          <({String id, String name})>[
            (id: 'AA:BB:CC:DD:EE:09', name: 'LE_WH-1000XM4'),
          ],
        ),
      },
    );

    // Stopped: the pencil stands where the signal readout would be.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byType(SignalStrengthIcon), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Los de correr');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Los de correr'), findsOneWidget);
    // The name the user chose replaces the advertised one, it does not join it.
    expect(find.text('LE_WH-1000XM4'), findsNothing);

    // Scanning: the pencil gives the corner back to the reading, and the chosen
    // name stays.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(SignalStrengthIcon), findsOneWidget);
    expect(find.text('Los de correr'), findsOneWidget);
  });

  testWidgets('opening the radar with the scan stopped rescans that device', (
    WidgetTester tester,
  ) async {
    final _FakeScanService service = _FakeScanService(
      seen: <DiscoveredDevice>[
        _device(id: 'AA:BB:CC:DD:EE:01', name: 'My buds', rssi: -60),
      ],
    );
    await _pumpApp(tester, scanService: service);

    expect(service.scanning, isFalse);

    await tester.tap(find.text('My buds'));
    // Pumped by hand, never settled: the radar sweep animates forever, so
    // `pumpAndSettle` would wait for a tree that is never going to be still.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RadarScreen), findsOneWidget);
    // The list keeps serving the last packet from before Stop; the radar is not
    // allowed to present that as a live reading, so it restarts the scan.
    expect(service.scanning, isTrue);

    // Leaving restores what the user had chosen instead of scanning behind
    // their back.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(service.scanning, isFalse);
  });
}
