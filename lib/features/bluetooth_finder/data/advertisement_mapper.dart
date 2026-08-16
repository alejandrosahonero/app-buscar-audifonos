import 'package:buscar_audifonos/features/bluetooth_finder/domain/advertisement_facts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Translates one plugin scan result into the plugin-free
/// [AdvertisementFacts] the domain reasons about.
///
/// This is the only place `flutter_blue_plus`' advertisement types are touched,
/// which is what lets the whole identification layer be unit tested without a
/// Bluetooth radio.
AdvertisementFacts advertisementFactsFrom(ScanResult result) {
  final AdvertisementData data = result.advertisementData;

  return AdvertisementFacts(
    // `platformName` is the cached GATT name (it survives across packets);
    // `advName` is what this particular advertisement carried. Either can be
    // empty, so prefer whichever we actually have.
    advertisedName: result.device.platformName.isNotEmpty
        ? result.device.platformName
        : data.advName,
    appearance: data.appearance,
    connectable: data.connectable,
    manufacturerData: data.manufacturerData,
    serviceData: _shortUuidKeyed(data.serviceData),
    serviceUuids: data.serviceUuids.map(_shortUuid).nonNulls.toSet(),
  );
}

Map<int, List<int>> _shortUuidKeyed(Map<Guid, List<int>> source) {
  final Map<int, List<int>> result = <int, List<int>>{};
  source.forEach((Guid uuid, List<int> payload) {
    final int? short = _shortUuid(uuid);
    if (short != null) result[short] = payload;
  });
  return result;
}

/// The 16-bit form of a UUID, or `null` when it is a 32/128-bit one.
///
/// `Guid.str` already collapses a UUID to its shortest representation, so a
/// four-character result is exactly the SIG-assigned 16-bit case — the only
/// kind we have a table for. Vendor-private 128-bit UUIDs carry nothing we
/// could label and are dropped.
int? _shortUuid(Guid uuid) {
  final String short = uuid.str;
  return short.length == 4 ? int.tryParse(short, radix: 16) : null;
}
