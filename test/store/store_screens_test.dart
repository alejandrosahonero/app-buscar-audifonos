// Raw app screens for the Play Store listing, rendered with the real fonts.
//
// Not part of the default run. Regenerate, then compose the framed images:
//
//   STORE=1 flutter test test/store --update-goldens
//   python tool/store/compose_listing.py
@Tags(<String>['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

final bool _enabled = Platform.environment.containsKey('STORE');

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final FontLoader loader = FontLoader(family);
    for (final String path in paths) {
      loader.addFont(
        Future<ByteData>.value(
          ByteData.sublistView(File(path).readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('Sora', <String>[
    'assets/fonts/Sora-300.ttf',
    'assets/fonts/Sora-600.ttf',
  ]);
  await load('Manrope', <String>[
    'assets/fonts/Manrope-400.ttf',
    'assets/fonts/Manrope-500.ttf',
    'assets/fonts/Manrope-700.ttf',
  ]);
  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  await load('MaterialIcons', <String>[
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

DiscoveredDevice _seen(
  String id,
  DeviceIdentity identity,
  int rssi, {
  bool paired = false,
  bool slow = false,
}) => DiscoveredDevice.firstSeen(
  id: id,
  identity: identity,
  rssi: rssi,
  isPaired: paired,
  isSlowSignal: slow,
  lastSeen: DateTime(2026),
);

final List<DiscoveredDevice> _room = <DiscoveredDevice>[
  _seen(
    'AA:00:00:00:00:01',
    const DeviceIdentity(
      advertisedName: 'AirPods Pro',
      modelName: 'AirPods Pro',
      vendor: 'Apple',
      category: DeviceCategory.earbuds,
      batteryPercent: 80,
    ),
    -36,
    paired: true,
  ),
  _seen(
    'AA:00:00:00:00:02',
    const DeviceIdentity(
      advertisedName: 'Galaxy Buds2 Pro',
      vendor: 'Samsung',
      category: DeviceCategory.earbuds,
      batteryPercent: 55,
    ),
    -58,
  ),
  _seen(
    'AA:00:00:00:00:03',
    const DeviceIdentity(
      advertisedName: 'JBL Flip 6',
      vendor: 'JBL',
      category: DeviceCategory.speaker,
    ),
    -66,
  ),
  _seen(
    'AA:00:00:00:00:04',
    const DeviceIdentity(
      advertisedName: 'Galaxy Watch6',
      vendor: 'Samsung',
      category: DeviceCategory.watch,
    ),
    -74,
  ),
  _seen(
    'AA:00:00:00:00:05',
    const DeviceIdentity(
      advertisedName: 'Manos libres BT',
      category: DeviceCategory.carKit,
    ),
    -84,
    slow: true,
  ),
];

final String _favourites = jsonEncode(<Object?>[
  const FavoriteDevice(
    id: 'AA:00:00:00:00:09',
    identity: DeviceIdentity(
      advertisedName: 'Sony WH-1000XM5',
      vendor: 'Sony',
      category: DeviceCategory.headphones,
    ),
  ).toJson(),
]);

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    await _loadFonts();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('xyz.luan/audioplayers.global/events'),
          MockStreamHandler.inline(
            onListen: (Object? _, MockStreamHandlerEventSink _) {},
          ),
        );
  });

  for (final String locale in <String>['es', 'en']) {
    testWidgets('welcome · $locale', (WidgetTester tester) async {
      await _phone(tester);
      await pumpApp(
        tester,
        scanService: FakeScanService(),
        settle: false,
        preferences: <String, Object>{
          'welcome_done': false,
          'app_locale': locale,
        },
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(locale == 'es' ? 'Siguiente' : 'Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('raw/${locale}_howto.png'),
      );
    }, skip: !_enabled);

    for (final String mode in <String>['dark', 'light']) {
      testWidgets('list · $locale · $mode', (WidgetTester tester) async {
        await _phone(tester);
        await pumpApp(
          tester,
          scanService: FakeScanService(seen: _room),
          settle: false,
          preferences: <String, Object>{
            'theme_mode': mode,
            'app_locale': locale,
            'finder_favorite_devices': _favourites,
          },
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.bluetooth_searching).first);
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('raw/${locale}_list_$mode.png'),
        );
      }, skip: !_enabled);
    }

    for (final (String name, String device) in <(String, String)>[
      ('radar_near', 'AirPods Pro'),
      ('radar_far', 'Galaxy Buds2 Pro'),
    ]) {
      testWidgets('$name · $locale', (WidgetTester tester) async {
        await _phone(tester);
        await pumpApp(
          tester,
          scanService: FakeScanService(seen: _room),
          settle: false,
          preferences: <String, Object>{
            'theme_mode': 'dark',
            'app_locale': locale,
          },
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.bluetooth_searching).first);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text(device).last);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 900));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('raw/${locale}_$name.png'),
        );
      }, skip: !_enabled);
    }
  }
}

/// A 393 × 852 phone at 2.75×, the size of a common mid-range Android.
Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}
