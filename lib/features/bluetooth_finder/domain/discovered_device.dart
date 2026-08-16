import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
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
    required this.identity,
    required this.rssi,
    required this.smoothedRssi,
    required this.lastSeen,
    this.isPaired = false,
  });

  /// Stable identifier: the MAC address on Android, a system-assigned UUID on
  /// iOS. Used to route to the radar and to key the list — **never rendered**.
  /// It is a long opaque number that tells a user nothing, and it identifies
  /// hardware, so it stays out of the UI entirely.
  final String id;

  /// What this device is, as far as its advertisement says. Carries the name,
  /// brand, kind and battery that the list actually displays.
  final DeviceIdentity identity;

  /// Already paired with this phone. Almost always the device being hunted for,
  /// so the list badges it.
  final bool isPaired;

  /// Latest raw reading, in dBm. Always negative; closer to zero means closer.
  final int rssi;

  /// Moving average of [rssi]. This is what the radar and the sound use — the
  /// raw value is far too noisy to steer by.
  final double smoothedRssi;

  final DateTime lastSeen;

  /// Closeness in 0..1, from the smoothed signal.
  double get closeness => Proximity.fromRssi(smoothedRssi);

  int get closenessPercent => Proximity.percent(smoothedRssi);

  ProximityBand get band => Proximity.bandFor(closeness);

  /// Folds a new advertisement into this device, keeping the moving average
  /// going. Returning a new instance (instead of mutating) keeps the value
  /// semantics the list relies on.
  DiscoveredDevice merge({
    required DeviceIdentity identity,
    required int rssi,
    required DateTime lastSeen,
    required bool isPaired,
  }) {
    return DiscoveredDevice(
      id: id,
      // Descriptions arrive piecemeal in BLE — never let a packet that omits
      // the name or the services erase what we already resolved.
      identity: this.identity.mergedWith(identity),
      isPaired: isPaired,
      rssi: rssi,
      smoothedRssi: Proximity.smooth(smoothedRssi, rssi),
      lastSeen: lastSeen,
    );
  }

  /// First sighting: the average starts at the sample itself, otherwise every
  /// device would fade in from "far away".
  factory DiscoveredDevice.firstSeen({
    required String id,
    required DeviceIdentity identity,
    required int rssi,
    required DateTime lastSeen,
    bool isPaired = false,
  }) {
    return DiscoveredDevice(
      id: id,
      identity: identity,
      isPaired: isPaired,
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
          other.identity == identity &&
          other.isPaired == isPaired &&
          other.rssi == rssi &&
          other.smoothedRssi == smoothedRssi &&
          other.lastSeen == lastSeen;

  @override
  int get hashCode =>
      Object.hash(id, identity, isPaired, rssi, smoothedRssi, lastSeen);
}
