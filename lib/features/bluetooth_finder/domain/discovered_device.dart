import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:flutter/foundation.dart';

/// A Bluetooth device seen by the scanner.
///
/// Immutable: every advertisement produces a new instance, which is what lets
/// the list rebuild only the tiles whose signal actually changed.
@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.smoothedRssi,
    required this.lastSeen,
  });

  /// Stable identifier: the MAC address on Android, a system-assigned UUID on
  /// iOS. Shown verbatim so the user can tell two identical earbuds apart.
  final String id;

  /// Advertised name, empty when the device only broadcasts its address. Plenty
  /// of earbuds advertise anonymously, hence the "hide unnamed" filter rather
  /// than dropping them outright.
  final String name;

  /// Latest raw reading, in dBm. Always negative; closer to zero means closer.
  final int rssi;

  /// Moving average of [rssi]. This is what the radar and the sound use — the
  /// raw value is far too noisy to steer by.
  final double smoothedRssi;

  final DateTime lastSeen;

  bool get hasName => name.isNotEmpty;

  /// Closeness in 0..1, from the smoothed signal.
  double get closeness => Proximity.fromRssi(smoothedRssi);

  int get closenessPercent => Proximity.percent(smoothedRssi);

  ProximityBand get band => Proximity.bandFor(closeness);

  /// Folds a new advertisement into this device, keeping the moving average
  /// going. Returning a new instance (instead of mutating) keeps the value
  /// semantics the list relies on.
  DiscoveredDevice merge({
    required String name,
    required int rssi,
    required DateTime lastSeen,
  }) {
    return DiscoveredDevice(
      id: id,
      // Names arrive late in BLE: the first packets often carry no name at all.
      // Never let an empty update erase a name we already resolved.
      name: name.isNotEmpty ? name : this.name,
      rssi: rssi,
      smoothedRssi: Proximity.smooth(smoothedRssi, rssi),
      lastSeen: lastSeen,
    );
  }

  /// First sighting: the average starts at the sample itself, otherwise every
  /// device would fade in from "far away".
  factory DiscoveredDevice.firstSeen({
    required String id,
    required String name,
    required int rssi,
    required DateTime lastSeen,
  }) {
    return DiscoveredDevice(
      id: id,
      name: name,
      rssi: rssi,
      smoothedRssi: rssi.toDouble(),
      lastSeen: lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          other.id == id &&
          other.name == name &&
          other.rssi == rssi &&
          other.smoothedRssi == smoothedRssi &&
          other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(id, name, rssi, smoothedRssi, lastSeen);
}
