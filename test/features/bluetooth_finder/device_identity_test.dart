import 'package:buscar_audifonos/features/bluetooth_finder/domain/advertisement_facts.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/bluetooth_registry.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A GAP appearance value: the top 10 bits are the category, the low 6 the
/// subcategory.
int _appearance(int category, [int subcategory = 0]) =>
    (category << 6) | subcategory;

void main() {
  group('DeviceIdentity.resolve — appearance', () {
    test('reads the wearable audio subcategories apart', () {
      expect(
        DeviceIdentity.resolve(
          AdvertisementFacts(appearance: _appearance(0x25, 0x01)),
        ).category,
        DeviceCategory.earbuds,
      );
      expect(
        DeviceIdentity.resolve(
          AdvertisementFacts(appearance: _appearance(0x25, 0x03)),
        ).category,
        DeviceCategory.headphones,
      );
    });

    test('recognises hearing aids and input devices', () {
      expect(
        DeviceIdentity.resolve(
          AdvertisementFacts(appearance: _appearance(0x29, 0x02)),
        ).category,
        DeviceCategory.hearingAid,
      );
      expect(
        DeviceIdentity.resolve(
          AdvertisementFacts(appearance: _appearance(0x0F, 0x01)),
        ).category,
        DeviceCategory.keyboard,
      );
      expect(
        DeviceIdentity.resolve(
          AdvertisementFacts(appearance: _appearance(0x0F, 0x02)),
        ).category,
        DeviceCategory.mouse,
      );
    });

    test('outranks a name that says otherwise', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        AdvertisementFacts(
          advertisedName: 'Keyboard',
          appearance: _appearance(0x25, 0x01),
        ),
      );

      expect(identity.category, DeviceCategory.earbuds);
    });
  });

  group('DeviceIdentity.resolve — manufacturer data', () {
    // Apple proximity pairing: type, length, prefix, then the model id.
    AdvertisementFacts appleProximity(int model) => AdvertisementFacts(
      manufacturerData: <int, List<int>>{
        0x004C: <int>[0x07, 0x19, 0x01, (model >> 8) & 0xFF, model & 0xFF],
      },
    );

    test('names a known AirPods model outright', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        appleProximity(0x200E),
      );

      expect(identity.modelName, 'AirPods Pro');
      expect(identity.vendor, 'Apple');
      expect(identity.category, DeviceCategory.earbuds);
      expect(identity.isIdentified, isTrue);
    });

    test('an unrecognised model still resolves to Apple earbuds', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        appleProximity(0xBEEF),
      );

      expect(identity.modelName, isNull);
      expect(identity.vendor, 'Apple');
      expect(identity.category, DeviceCategory.earbuds);
    });

    test('a Find My broadcast on its own reads as a tracker', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          manufacturerData: <int, List<int>>{
            0x004C: <int>[0x12, 0x19, 0x00],
          },
        ),
      );

      expect(identity.category, DeviceCategory.tracker);
      expect(identity.traits, contains(DeviceTrait.findMy));
    });

    test(
      'Find My never overrides a category some better source established',
      () {
        // A lost AirPod broadcasts on the Find My network exactly like an
        // AirTag. It is still a pair of earbuds.
        final DeviceIdentity identity = DeviceIdentity.resolve(
          AdvertisementFacts(
            appearance: _appearance(0x25, 0x01),
            manufacturerData: const <int, List<int>>{
              0x004C: <int>[0x12, 0x19, 0x00],
            },
          ),
        );

        expect(identity.category, DeviceCategory.earbuds);
        expect(identity.traits, contains(DeviceTrait.findMy));
      },
    );

    test('flags a Microsoft Swift Pair beacon', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          manufacturerData: <int, List<int>>{
            0x0006: <int>[0x03, 0x00],
          },
        ),
      );

      expect(identity.vendor, 'Microsoft');
      expect(identity.traits, contains(DeviceTrait.swiftPair));
    });

    test('chipset makers are not passed off as brands', () {
      // Cambridge Silicon Radio: the chip inside half the cheap earbuds on the
      // market, and never the name on the box.
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          manufacturerData: <int, List<int>>{
            0x000A: <int>[0x01],
          },
        ),
      );

      expect(identity.vendor, isNull);
    });
  });

  group('DeviceIdentity.resolve — services', () {
    test('the Hearing Access Service is proof of a hearing aid', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          serviceUuids: <int>{BluetoothRegistry.hearingAccess},
        ),
      );

      expect(identity.category, DeviceCategory.hearingAid);
      expect(identity.traits, contains(DeviceTrait.hearingAid));
    });

    test('the Find Me plus Link Loss pair reads as a key finder', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          serviceUuids: <int>{
            BluetoothRegistry.immediateAlert,
            BluetoothRegistry.linkLoss,
          },
        ),
      );

      expect(identity.category, DeviceCategory.tracker);
    });

    test('Fast Pair is reported as a trait, not as a device kind', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          serviceUuids: <int>{BluetoothRegistry.fastPair},
        ),
      );

      expect(identity.traits, contains(DeviceTrait.fastPair));
      expect(identity.category, DeviceCategory.unknown);
    });
  });

  group('DeviceIdentity.resolve — battery', () {
    test('reads the Battery Service level', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          serviceData: <int, List<int>>{
            BluetoothRegistry.batteryService: <int>[78],
          },
        ),
      );

      expect(identity.batteryPercent, 78);
    });

    test('drops a level outside 0-100 rather than showing nonsense', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          serviceData: <int, List<int>>{
            BluetoothRegistry.batteryService: <int>[255],
          },
        ),
      );

      expect(identity.batteryPercent, isNull);
    });
  });

  group('DeviceIdentity.resolve — advertised name', () {
    test('is the last resort, behind every standards-based source', () {
      expect(
        DeviceIdentity.resolve(
          const AdvertisementFacts(advertisedName: 'Galaxy Buds Pro'),
        ).category,
        DeviceCategory.earbuds,
      );
      expect(
        DeviceIdentity.resolve(
          const AdvertisementFacts(advertisedName: 'Ratón de Ana'),
        ).category,
        DeviceCategory.mouse,
      );
    });

    test('matching ignores case and Spanish accents', () {
      expect(
        DeviceIdentity.resolve(
          const AdvertisementFacts(advertisedName: 'AURICULARES SALÓN'),
        ).category,
        DeviceCategory.headphones,
      );
    });
  });

  group('DeviceIdentity.isIdentified', () {
    test('a brand alone is not enough to survive the filter', () {
      // Every iPhone in the room advertises as Apple and says nothing else.
      final DeviceIdentity identity = DeviceIdentity.resolve(
        const AdvertisementFacts(
          manufacturerData: <int, List<int>>{
            0x004C: <int>[0x10, 0x05],
          },
        ),
      );

      expect(identity.vendor, 'Apple');
      expect(identity.isIdentified, isFalse);
    });

    test('a brand plus a known kind of device is', () {
      final DeviceIdentity identity = DeviceIdentity.resolve(
        AdvertisementFacts(
          appearance: _appearance(0x25, 0x01),
          manufacturerData: const <int, List<int>>{
            0x004C: <int>[0x10, 0x05],
          },
        ),
      );

      expect(identity.isIdentified, isTrue);
    });

    test('nothing at all is not', () {
      expect(
        DeviceIdentity.resolve(AdvertisementFacts.empty).isIdentified,
        isFalse,
      );
    });
  });

  group('DeviceIdentity.mergedWith', () {
    test('keeps what a later half-empty packet leaves out', () {
      const DeviceIdentity known = DeviceIdentity(
        advertisedName: 'WH-1000XM4',
        vendor: 'Sony',
        category: DeviceCategory.headphones,
        batteryPercent: 90,
        traits: <DeviceTrait>{DeviceTrait.leAudio},
      );

      final DeviceIdentity merged = known.mergedWith(DeviceIdentity.unknown);

      expect(merged.advertisedName, 'WH-1000XM4');
      expect(merged.vendor, 'Sony');
      expect(merged.category, DeviceCategory.headphones);
      expect(merged.batteryPercent, 90);
      expect(merged.traits, contains(DeviceTrait.leAudio));
    });

    test('takes newer values and accumulates traits', () {
      const DeviceIdentity known = DeviceIdentity(
        vendor: 'Sony',
        batteryPercent: 90,
        traits: <DeviceTrait>{DeviceTrait.leAudio},
      );

      final DeviceIdentity merged = known.mergedWith(
        const DeviceIdentity(
          advertisedName: 'WH-1000XM4',
          category: DeviceCategory.headphones,
          batteryPercent: 88,
          traits: <DeviceTrait>{DeviceTrait.fastPair},
        ),
      );

      expect(merged.advertisedName, 'WH-1000XM4');
      expect(merged.category, DeviceCategory.headphones);
      expect(merged.batteryPercent, 88);
      expect(merged.traits, <DeviceTrait>{
        DeviceTrait.leAudio,
        DeviceTrait.fastPair,
      });
    });
  });
}
