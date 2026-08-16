import 'package:flutter/foundation.dart';

/// One BLE advertisement, stripped of the scanning plugin's types.
///
/// The `data` layer maps `flutter_blue_plus`' `AdvertisementData` onto this, so
/// `DeviceIdentity.resolve` — and its tests — never touch the plugin. Keeps the
/// dependency rule intact: `domain` knows nobody.
///
/// Note what is *not* here: the remote address. Identification never needs it,
/// and leaving it out of the domain makes it impossible to leak into the UI by
/// accident.
@immutable
class AdvertisementFacts {
  const AdvertisementFacts({
    this.advertisedName = '',
    this.appearance,
    this.connectable = false,
    this.manufacturerData = const <int, List<int>>{},
    this.serviceData = const <int, List<int>>{},
    this.serviceUuids = const <int>{},
  });

  static const AdvertisementFacts empty = AdvertisementFacts();

  /// Name carried by this packet, or the cached GATT name. Often empty: BLE
  /// splits the name into the scan response, which arrives a beat later.
  final String advertisedName;

  /// 16-bit GAP appearance. The single most reliable type hint there is,
  /// because it is a value the manufacturer chose from the SIG's own list.
  /// Android only — iOS never surfaces it.
  final int? appearance;

  /// The advertiser accepts connections (as opposed to a broadcast-only tag).
  final bool connectable;

  /// Company identifier → payload, with the company id already stripped.
  final Map<int, List<int>> manufacturerData;

  /// Service data keyed by **16-bit** UUID. 128-bit entries are dropped: they
  /// are vendor-private and carry nothing we can label.
  final Map<int, List<int>> serviceData;

  /// Advertised 16-bit service UUIDs.
  final Set<int> serviceUuids;
}
