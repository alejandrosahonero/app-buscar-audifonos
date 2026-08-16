import 'package:buscar_audifonos/features/bluetooth_finder/domain/advertisement_facts.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/bluetooth_registry.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:flutter/foundation.dart';

/// Everything useful an advertisement says about *what* a device is.
///
/// The rule this class exists to enforce: the list shows facts a person can act
/// on — a brand, a kind of thing, a battery level — and never the identifiers
/// underneath them. Addresses, rotating identifiers and raw payloads are read
/// to produce this object and then thrown away.
@immutable
class DeviceIdentity {
  const DeviceIdentity({
    this.category = DeviceCategory.unknown,
    this.traits = const <DeviceTrait>{},
    this.advertisedName = '',
    this.modelName,
    this.vendor,
    this.batteryPercent,
    this.connectable = false,
  });

  static const DeviceIdentity unknown = DeviceIdentity();

  /// The name the device broadcasts, verbatim. Usually the best label there is:
  /// people rename their earbuds.
  final String advertisedName;

  /// Product name we recognised without being told, e.g. `AirPods Pro`.
  final String? modelName;

  /// Consumer brand behind the company identifier, e.g. `Sony`.
  final String? vendor;

  final DeviceCategory category;

  final Set<DeviceTrait> traits;

  /// Charge level, 0-100, only when the device advertises the standard Battery
  /// Service. Never inferred.
  final int? batteryPercent;

  /// Accepts connections. A broadcast-only advertiser cannot be paired with.
  final bool connectable;

  bool get hasAdvertisedName => advertisedName.isNotEmpty;

  /// Whether we can tell the user something real about this device.
  ///
  /// A bare vendor is deliberately *not* enough: every iPhone in the room
  /// advertises as Apple with no type and no name, and letting those through
  /// would bury the earbuds the user is actually looking for. It takes a name,
  /// a recognised model, or a brand *and* a known kind of device.
  bool get isIdentified =>
      hasAdvertisedName ||
      modelName != null ||
      (vendor != null && category != DeviceCategory.unknown);

  /// Reads one advertisement, most reliable evidence first.
  ///
  /// Order matters and is not arbitrary:
  /// 1. **GAP appearance** — a value the manufacturer picked from the SIG's own
  ///    list. When present it is simply correct.
  /// 2. **Manufacturer data** — Apple and Microsoft describe their own devices
  ///    precisely, which is how AirPods get a real name.
  /// 3. **Advertised services** — standards-based and unambiguous, but a device
  ///    only lists the services it feels like listing.
  /// 4. **The advertised name** — guesswork, so it goes last.
  factory DeviceIdentity.resolve(AdvertisementFacts facts) {
    final Set<DeviceTrait> traits = <DeviceTrait>{
      ...BluetoothRegistry.traitsForServices(facts.serviceUuids),
    };

    String? vendor;
    String? modelName;
    DeviceCategory fromVendor = DeviceCategory.unknown;
    // Evidence that only applies when nothing better turned up. A lost AirPod
    // broadcasts on the Find My network exactly like an AirTag does, so "this
    // is a tracker" must never overrule "this is a pair of earbuds".
    DeviceCategory fromVendorFallback = DeviceCategory.unknown;

    for (final MapEntry<int, List<int>> entry
        in facts.manufacturerData.entries) {
      vendor ??= BluetoothRegistry.vendorFor(entry.key);
      final List<int> payload = entry.value;
      if (payload.isEmpty) continue;

      switch (entry.key) {
        case _appleCompanyId:
          switch (payload.first) {
            // Proximity pairing: the record AirPods and Beats broadcast while
            // they wait to be picked up. Bytes 3-4 are the model.
            case _appleProximityPairing:
              fromVendor = DeviceCategory.earbuds;
              if (payload.length >= 5) {
                final KnownModel? model = BluetoothRegistry.appleModel(
                  (payload[3] << 8) | payload[4],
                );
                if (model != null) {
                  modelName = model.name;
                  fromVendor = model.category;
                }
              }
            case _appleFindMy:
              traits.add(DeviceTrait.findMy);
              fromVendorFallback = DeviceCategory.tracker;
            case _appleIBeacon:
              traits.add(DeviceTrait.beacon);
              fromVendorFallback = DeviceCategory.beacon;
          }
        case _microsoftCompanyId:
          if (payload.first == _microsoftSwiftPair) {
            traits.add(DeviceTrait.swiftPair);
          }
      }
    }

    final DeviceCategory category = _firstKnown(<DeviceCategory>[
      if (facts.appearance != null)
        BluetoothRegistry.categoryForAppearance(facts.appearance!),
      fromVendor,
      BluetoothRegistry.categoryForServices(facts.serviceUuids),
      BluetoothRegistry.categoryForName(facts.advertisedName),
      fromVendorFallback,
    ]);

    return DeviceIdentity(
      advertisedName: facts.advertisedName,
      modelName: modelName,
      vendor: vendor,
      category: category,
      traits: traits,
      batteryPercent: _batteryFrom(facts),
      connectable: facts.connectable,
    );
  }

  /// Folds a fresh reading into what we already knew.
  ///
  /// BLE splits a device's description across the advertisement and the scan
  /// response, and the two arrive as separate packets: the first may carry the
  /// services and the next only the name. Resolving each packet in isolation
  /// would make the tile flicker between two half-identities, so known values
  /// are sticky and traits accumulate. A new scan starts from scratch, which is
  /// what keeps this from going stale.
  DeviceIdentity mergedWith(DeviceIdentity next) => DeviceIdentity(
    advertisedName: next.hasAdvertisedName
        ? next.advertisedName
        : advertisedName,
    modelName: next.modelName ?? modelName,
    vendor: next.vendor ?? vendor,
    category: next.category != DeviceCategory.unknown
        ? next.category
        : category,
    traits: <DeviceTrait>{...traits, ...next.traits},
    batteryPercent: next.batteryPercent ?? batteryPercent,
    connectable: next.connectable || connectable,
  );

  /// Apple, Microsoft and the payload markers we read inside their data.
  static const int _appleCompanyId = 0x004C;
  static const int _appleProximityPairing = 0x07;
  static const int _appleFindMy = 0x12;
  static const int _appleIBeacon = 0x02;
  static const int _microsoftCompanyId = 0x0006;
  static const int _microsoftSwiftPair = 0x03;

  static DeviceCategory _firstKnown(List<DeviceCategory> candidates) {
    for (final DeviceCategory candidate in candidates) {
      if (candidate != DeviceCategory.unknown) return candidate;
    }
    return DeviceCategory.unknown;
  }

  /// Battery Service data is a single byte holding the percentage. Anything
  /// outside 0-100 is a malformed packet and is dropped rather than shown.
  static int? _batteryFrom(AdvertisementFacts facts) {
    final List<int>? payload =
        facts.serviceData[BluetoothRegistry.batteryService];
    if (payload == null || payload.isEmpty) return null;
    final int level = payload.first;
    return level >= 0 && level <= 100 ? level : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceIdentity &&
          other.advertisedName == advertisedName &&
          other.modelName == modelName &&
          other.vendor == vendor &&
          other.category == category &&
          other.batteryPercent == batteryPercent &&
          other.connectable == connectable &&
          other.traits.length == traits.length &&
          other.traits.containsAll(traits);

  @override
  int get hashCode => Object.hash(
    advertisedName,
    modelName,
    vendor,
    category,
    batteryPercent,
    connectable,
    Object.hashAllUnordered(traits),
  );
}
