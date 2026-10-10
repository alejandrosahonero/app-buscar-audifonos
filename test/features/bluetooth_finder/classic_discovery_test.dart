import 'package:buscar_audifonos/features/bluetooth_finder/domain/bluetooth_registry.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BluetoothRegistry.categoryForClassOfDevice', () {
    test('reads the audio classes a headset declares', () {
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0404),
        DeviceCategory.earbuds,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0418),
        DeviceCategory.headphones,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0414),
        DeviceCategory.speaker,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0420),
        DeviceCategory.carKit,
      );
    });

    test('reads the other major classes', () {
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x020C),
        DeviceCategory.phone,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0540),
        DeviceCategory.keyboard,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0580),
        DeviceCategory.mouse,
      );
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0x0704),
        DeviceCategory.watch,
      );
    });

    test('an unset class is unknown, not a guess', () {
      expect(
        BluetoothRegistry.categoryForClassOfDevice(0),
        DeviceCategory.unknown,
      );
    });
  });

  group('DeviceIdentity.fromClassic', () {
    test('the class of device outranks the name', () {
      final DeviceIdentity identity = DeviceIdentity.fromClassic(
        name: 'Altavoz salón',
        deviceClass: 0x0418,
      );
      expect(identity.category, DeviceCategory.headphones);
      expect(identity.advertisedName, 'Altavoz salón');
    });

    test('falls back to the name when the class says nothing', () {
      final DeviceIdentity identity = DeviceIdentity.fromClassic(
        name: 'Mis audifonos',
        deviceClass: 0,
      );
      expect(
        identity.category,
        BluetoothRegistry.categoryForName('Mis audifonos'),
      );
    });
  });

  group('slow signal', () {
    test('a classic reading is shown as it arrives, not averaged', () {
      final DiscoveredDevice first = DiscoveredDevice.firstSeen(
        id: 'AA:BB:CC:DD:EE:01',
        identity: DeviceIdentity.unknown,
        isSlowSignal: true,
        rssi: -90,
        lastSeen: DateTime(2026),
      );
      final DiscoveredDevice next = first.merge(
        identity: DeviceIdentity.unknown,
        isPaired: false,
        rssi: -50,
        lastSeen: DateTime(2026, 1, 1, 0, 0, 12),
      );
      expect(next.isSlowSignal, isTrue);
      expect(next.smoothedRssi, -50);
    });

    test('a BLE reading is still averaged', () {
      final DiscoveredDevice next =
          DiscoveredDevice.firstSeen(
            id: 'AA:BB:CC:DD:EE:01',
            identity: DeviceIdentity.unknown,
            rssi: -90,
            lastSeen: DateTime(2026),
          ).merge(
            identity: DeviceIdentity.unknown,
            isPaired: false,
            rssi: -50,
            lastSeen: DateTime(2026),
          );
      expect(next.smoothedRssi, isNot(-50));
    });

    test('a classic favourite remembers it through storage', () {
      final FavoriteDevice favorite = FavoriteDevice.fromDiscovered(
        DiscoveredDevice.firstSeen(
          id: 'AA:BB:CC:DD:EE:01',
          identity: DeviceIdentity.unknown,
          isSlowSignal: true,
          rssi: -60,
          lastSeen: DateTime(2026),
        ),
      );
      expect(favorite.isClassic, isTrue);
      expect(FavoriteDevice.fromJson(favorite.toJson())?.isClassic, isTrue);
      expect(favorite.renamedTo('Los del gym').isClassic, isTrue);
    });

    test('favourites saved before classic support read as BLE', () {
      final FavoriteDevice? favorite = FavoriteDevice.fromJson(
        <String, Object?>{'id': 'AA:BB:CC:DD:EE:01', 'name': 'Viejos'},
      );
      expect(favorite?.isClassic, isFalse);
    });
  });
}
