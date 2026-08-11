import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:flutter/foundation.dart';

/// What the user chose to see in the device list.
///
/// A busy street produces dozens of anonymous beacons per minute. Both filters
/// are on by default because the app is a *finder*: the target is almost always
/// a named device the user is standing near.
@immutable
class ScanFilter {
  const ScanFilter({this.hideUnnamed = true, this.hideWeakSignal = true});

  /// Anything below this is too far to walk towards: the reading is dominated
  /// by noise and the radar would send the user in a random direction.
  static const int weakSignalThreshold = -95;

  final bool hideUnnamed;
  final bool hideWeakSignal;

  ScanFilter copyWith({bool? hideUnnamed, bool? hideWeakSignal}) => ScanFilter(
    hideUnnamed: hideUnnamed ?? this.hideUnnamed,
    hideWeakSignal: hideWeakSignal ?? this.hideWeakSignal,
  );

  bool allows(DiscoveredDevice device) {
    if (hideUnnamed && !device.hasName) return false;
    // Filtered on the smoothed value: a single unlucky packet should not make a
    // device blink out of the list.
    if (hideWeakSignal && device.smoothedRssi < weakSignalThreshold) {
      return false;
    }
    return true;
  }

  /// Applies the filter and sorts by signal strength, strongest first — the
  /// device the user is looking for is the one they are walking towards.
  List<DiscoveredDevice> apply(List<DiscoveredDevice> devices) {
    final List<DiscoveredDevice> visible = devices.where(allows).toList();
    visible.sort(
      (DiscoveredDevice a, DiscoveredDevice b) =>
          b.smoothedRssi.compareTo(a.smoothedRssi),
    );
    return visible;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanFilter &&
          other.hideUnnamed == hideUnnamed &&
          other.hideWeakSignal == hideWeakSignal;

  @override
  int get hashCode => Object.hash(hideUnnamed, hideWeakSignal);
}
