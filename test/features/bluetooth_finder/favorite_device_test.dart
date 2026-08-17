import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FavoriteDevice.fromDiscovered', () {
    test('keeps what describes the device', () {
      final FavoriteDevice favorite = FavoriteDevice.fromDiscovered(
        DiscoveredDevice.firstSeen(
          id: 'AA:BB:CC:DD:EE:01',
          identity: const DeviceIdentity(
            advertisedName: 'Mis auriculares',
            modelName: 'AirPods Pro',
            vendor: 'Apple',
            category: DeviceCategory.earbuds,
          ),
          rssi: -50,
          lastSeen: DateTime(2026),
        ),
      );

      expect(favorite.id, 'AA:BB:CC:DD:EE:01');
      expect(favorite.identity.advertisedName, 'Mis auriculares');
      expect(favorite.identity.modelName, 'AirPods Pro');
      expect(favorite.identity.vendor, 'Apple');
      expect(favorite.identity.category, DeviceCategory.earbuds);
    });

    test('drops what only described the packet it arrived in', () {
      final FavoriteDevice favorite = FavoriteDevice.fromDiscovered(
        DiscoveredDevice.firstSeen(
          id: 'AA:BB:CC:DD:EE:01',
          identity: const DeviceIdentity(
            advertisedName: 'Mis auriculares',
            batteryPercent: 80,
            connectable: true,
            traits: <DeviceTrait>{DeviceTrait.fastPair},
          ),
          rssi: -50,
          lastSeen: DateTime(2026),
        ),
      );

      // A saved "80 %" next to a device nobody can hear would be a reading the
      // app does not have.
      expect(favorite.identity.batteryPercent, isNull);
      expect(favorite.identity.connectable, isFalse);
      expect(favorite.identity.traits, isEmpty);
    });
  });

  group('FavoriteDevice serialization', () {
    test('survives a round trip', () {
      const FavoriteDevice favorite = FavoriteDevice(
        id: 'AA:BB:CC:DD:EE:01',
        identity: DeviceIdentity(
          advertisedName: 'Mis auriculares',
          modelName: 'WF-1000XM5',
          vendor: 'Sony',
          category: DeviceCategory.earbuds,
        ),
      );

      expect(FavoriteDevice.fromJson(favorite.toJson()), favorite);
    });

    test('stores the category by name, not by index', () {
      const FavoriteDevice favorite = FavoriteDevice(
        id: 'AA:BB:CC:DD:EE:01',
        identity: DeviceIdentity(category: DeviceCategory.hearingAid),
      );

      expect(favorite.toJson()['category'], 'hearingAid');
    });

    test('degrades an unknown category instead of failing', () {
      final FavoriteDevice? favorite = FavoriteDevice.fromJson(
        <String, Object?>{'id': 'AA:BB:CC:DD:EE:01', 'category': 'jetpack'},
      );

      expect(favorite?.identity.category, DeviceCategory.unknown);
    });

    test('rejects a row with no usable identifier', () {
      expect(
        FavoriteDevice.fromJson(<String, Object?>{'name': 'orphan'}),
        null,
      );
      expect(FavoriteDevice.fromJson(<String, Object?>{'id': ''}), null);
      expect(FavoriteDevice.fromJson('not a favourite'), null);
    });
  });
}
