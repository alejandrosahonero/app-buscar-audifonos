import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:flutter/foundation.dart';

/// A device the user pinned to the top of the list.
///
/// The point of a favourite is that it shows up **even when nothing is heard
/// from it** — a switched-off earbud is precisely the one the user wants to
/// find. That means this object has to carry its own description, because there
/// is no advertisement to resolve one from.
///
/// Only the stable half of a [DeviceIdentity] is kept. Battery, traits and
/// connectability describe *this* advertisement, not the device, and a stale
/// "80 %" next to an offline row would be a lie.
@immutable
class FavoriteDevice {
  const FavoriteDevice({
    required this.id,
    required this.identity,
    this.customName,
  });

  /// Same identifier as [DiscoveredDevice.id]: the MAC on Android, a
  /// system-assigned UUID on iOS. Stored so the device can be recognised again
  /// on the next scan, kept in app-private storage, and — like everywhere else
  /// in this feature — **never rendered**.
  final String id;

  /// Snapshot taken when the device was pinned. Used as the label whenever the
  /// device is not currently advertising; a live reading always wins over it.
  final DeviceIdentity identity;

  /// The name the user typed for this device, or `null` to keep using the
  /// advertised one.
  ///
  /// Two devices of the same model advertise the same name — "LE_WH-1000XM4"
  /// twice tells the user nothing about which one is theirs. This is the only
  /// piece of a favourite the user authors, so it outranks every resolved name
  /// and it survives a re-pin.
  final String? customName;

  /// Keeps the name, the model, the brand and the kind; drops everything that
  /// only describes the packet it came from.
  factory FavoriteDevice.fromDiscovered(
    DiscoveredDevice device, {
    String? customName,
  }) {
    return FavoriteDevice(
      id: device.id,
      customName: customName,
      identity: DeviceIdentity(
        advertisedName: device.identity.advertisedName,
        modelName: device.identity.modelName,
        vendor: device.identity.vendor,
        category: device.identity.category,
      ),
    );
  }

  /// Same favourite under another name. `null` clears the custom one.
  FavoriteDevice renamedTo(String? name) => FavoriteDevice(
    id: id,
    identity: identity,
    customName: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    _idKey: id,
    _nameKey: identity.advertisedName,
    if (customName != null) _customNameKey: customName,
    _modelKey: identity.modelName,
    _vendorKey: identity.vendor,
    // The enum's *name*, not its index: the taxonomy is expected to grow, and
    // an index would silently re-label every stored favourite the day a
    // category is inserted in the middle.
    _categoryKey: identity.category.name,
  };

  /// Returns `null` for anything that does not read back as a favourite —
  /// hand-edited preferences, or a format from a future version. A dropped row
  /// costs the user one long-press; a thrown exception would cost them the
  /// whole list.
  static FavoriteDevice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;

    final Object? id = json[_idKey];
    if (id is! String || id.isEmpty) return null;

    final Object? custom = json[_customNameKey];

    return FavoriteDevice(
      id: id,
      customName: custom is String && custom.trim().isNotEmpty
          ? custom.trim()
          : null,
      identity: DeviceIdentity(
        advertisedName: json[_nameKey] is String
            ? json[_nameKey]! as String
            : '',
        modelName: json[_modelKey] is String
            ? json[_modelKey]! as String
            : null,
        vendor: json[_vendorKey] is String ? json[_vendorKey]! as String : null,
        category: _categoryFrom(json[_categoryKey]),
      ),
    );
  }

  static DeviceCategory _categoryFrom(Object? value) {
    for (final DeviceCategory category in DeviceCategory.values) {
      if (category.name == value) return category;
    }
    return DeviceCategory.unknown;
  }

  static const String _idKey = 'id';
  static const String _nameKey = 'name';
  static const String _customNameKey = 'customName';
  static const String _modelKey = 'model';
  static const String _vendorKey = 'vendor';
  static const String _categoryKey = 'category';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteDevice &&
          other.id == id &&
          other.identity == identity &&
          other.customName == customName;

  @override
  int get hashCode => Object.hash(id, identity, customName);
}
