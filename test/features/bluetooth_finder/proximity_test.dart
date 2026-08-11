import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/scan_filter.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoveredDevice _device({String name = 'Buds', required int rssi}) =>
    DiscoveredDevice.firstSeen(
      id: 'AA:BB:CC:DD:EE:FF',
      name: name,
      rssi: rssi,
      lastSeen: DateTime(2026),
    );

void main() {
  group('Proximity', () {
    test('maps the useful RSSI range onto 0..100 %', () {
      expect(Proximity.percent(-100), 0);
      expect(Proximity.percent(-65), 50);
      expect(Proximity.percent(-30), 100);
    });

    test('clamps readings outside the useful range', () {
      expect(Proximity.percent(-130), 0);
      expect(Proximity.percent(-10), 100);
    });

    test('bands follow the red / amber / green thresholds', () {
      expect(Proximity.bandFor(0.1), ProximityBand.far);
      expect(Proximity.bandFor(0.5), ProximityBand.near);
      expect(Proximity.bandFor(0.9), ProximityBand.veryNear);
    });

    test('the click interval accelerates as the device gets closer', () {
      final Duration far = Proximity.clickInterval(0);
      final Duration mid = Proximity.clickInterval(0.5);
      final Duration close = Proximity.clickInterval(1);

      expect(far, greaterThan(mid));
      expect(mid, greaterThan(close));
      expect(close.inMilliseconds, greaterThan(0));
    });

    test('smoothing converges towards the samples without overshooting', () {
      double average = -90;
      for (int i = 0; i < 40; i++) {
        average = Proximity.smooth(average, -50);
      }

      expect(average, closeTo(-50, 0.5));
    });
  });

  group('DiscoveredDevice', () {
    test('a first sighting starts its average at the sample itself', () {
      expect(_device(rssi: -70).smoothedRssi, -70);
    });

    test('merging never erases a name with a later empty advertisement', () {
      final DiscoveredDevice merged = _device(
        rssi: -70,
      ).merge(name: '', rssi: -68, lastSeen: DateTime(2026, 1, 2));

      expect(merged.name, 'Buds');
      expect(merged.rssi, -68);
    });

    test('merging moves the average towards the new sample', () {
      final DiscoveredDevice merged = _device(
        rssi: -90,
      ).merge(name: 'Buds', rssi: -50, lastSeen: DateTime(2026, 1, 2));

      expect(merged.smoothedRssi, greaterThan(-90));
      expect(merged.smoothedRssi, lessThan(-50));
    });
  });

  group('ScanFilter', () {
    test('the defaults drop unnamed and very weak devices', () {
      const ScanFilter filter = ScanFilter();

      expect(filter.allows(_device(rssi: -50)), isTrue);
      expect(filter.allows(_device(name: '', rssi: -50)), isFalse);
      expect(filter.allows(_device(rssi: -99)), isFalse);
    });

    test('turning both filters off lets everything through', () {
      const ScanFilter filter = ScanFilter(
        hideUnnamed: false,
        hideWeakSignal: false,
      );

      expect(filter.allows(_device(name: '', rssi: -110)), isTrue);
    });

    test('apply sorts by signal strength, strongest first', () {
      const ScanFilter filter = ScanFilter();
      final List<DiscoveredDevice> sorted = filter.apply(<DiscoveredDevice>[
        _device(name: 'weak', rssi: -80),
        _device(name: 'strong', rssi: -40),
        _device(name: 'mid', rssi: -60),
      ]);

      expect(sorted.map((DiscoveredDevice d) => d.name), <String>[
        'strong',
        'mid',
        'weak',
      ]);
    });
  });
}
