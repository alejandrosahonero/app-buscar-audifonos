import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';

/// A model this app can name outright, plus what it is.
typedef KnownModel = ({String name, DeviceCategory category});

/// Lookup tables that turn the numbers inside an advertisement into words.
///
/// Everything here is a *curated subset* of the Bluetooth SIG's assigned
/// numbers, not a mirror of them. The full company list is ~4000 entries of
/// mostly industrial suppliers; shipping it would add weight for names no user
/// would recognise. Unknown values simply resolve to `null` /
/// [DeviceCategory.unknown], which the UI renders as a neutral fallback.
abstract final class BluetoothRegistry {
  // --------------------------------------------------------------------
  // Well-known 16-bit service UUIDs
  // --------------------------------------------------------------------

  /// Battery Service. Its *service data* is a single byte: the charge level.
  static const int batteryService = 0x180F;

  /// Hearing Access Service — definitive proof of a hearing aid.
  static const int hearingAccess = 0x1854;

  static const int humanInterfaceDevice = 0x1812;
  static const int immediateAlert = 0x1802;
  static const int linkLoss = 0x1803;

  /// Google Fast Pair.
  static const int fastPair = 0xFE2C;

  /// Eddystone beacons and the COVID-era Exposure Notification service: both
  /// are stationary or system broadcasts, never a lost pair of earbuds.
  static const int eddystone = 0xFEAA;
  static const int exposureNotification = 0xFD6F;

  /// Tile's two advertised services.
  static const Set<int> _tile = <int>{0xFEED, 0xFEEC};

  /// Bluetooth LE Audio. An acceptor advertising these is a sink you wear or
  /// listen to.
  static const Set<int> _leAudio = <int>{
    0x1844, // Volume Control
    0x184D, // Microphone Control
    0x184E, // Audio Stream Control
    0x1850, // Published Audio Capabilities
    0x1853, // Common Audio
    0x1855, // Telephony and Media Audio
  };

  static const Set<int> _health = <int>{
    0x1808, // Glucose
    0x1809, // Health Thermometer
    0x180D, // Heart Rate
    0x1810, // Blood Pressure
    0x181B, // Body Composition
    0x181D, // Weight Scale
    0x181F, // Continuous Glucose Monitoring
    0x1822, // Pulse Oximeter
    0x183A, // Insulin Delivery
  };

  static const Set<int> _fitness = <int>{
    0x1814, // Running Speed and Cadence
    0x1816, // Cycling Speed and Cadence
    0x1818, // Cycling Power
    0x1826, // Fitness Machine
    0x183E, // Physical Activity Monitor
  };

  // --------------------------------------------------------------------
  // Company identifiers
  // --------------------------------------------------------------------

  /// Consumer brand behind a company identifier, or `null` when we have no
  /// name a user would recognise.
  ///
  /// Two rules keep this honest:
  ///
  /// * **Chipset makers are excluded on purpose.** Half the cheap earbuds on
  ///   the market advertise as Cambridge Silicon Radio, Realtek, Bluetrum or
  ///   Actions. Those are the chip inside, not the brand on the box, and
  ///   labelling a no-name earbud "Qualcomm" would be a confident lie.
  /// * **Holding companies resolve to their dominant consumer brand** (Sonova →
  ///   Phonak, Sivantos → Signia), *except* where a group has several co-equal
  ///   brands — Harman owns JBL, AKG and Harman Kardon alike, so it stays
  ///   "Harman" rather than guessing one of the three.
  static String? vendorFor(int companyId) => _companies[companyId];

  static const Map<int, String> _companies = <int, String>{
    0x0006: 'Microsoft',
    0x0008: 'Motorola',
    0x003A: 'Panasonic',
    0x004C: 'Apple',
    0x0055: 'Poly', // Plantronics
    0x0056: 'Sony',
    0x0057: 'Harman', // JBL / AKG / Harman Kardon
    0x0067: 'ReSound', // GN Hearing
    0x0089: 'ReSound',
    0x006B: 'Polar',
    0x0075: 'Samsung',
    0x0087: 'Garmin',
    0x009E: 'Bose',
    0x009F: 'Suunto',
    0x00BA: 'Starkey',
    0x00C4: 'LG',
    0x00CC: 'Beats',
    0x00D1: 'Polar',
    0x00D9: 'Turtle Beach',
    0x00E0: 'Google',
    0x0103: 'Bang & Olufsen',
    0x0107: 'Oticon', // Demant
    0x0111: 'SteelSeries',
    0x011B: 'HP',
    0x011F: 'Volkswagen',
    0x012D: 'Sony',
    0x0150: 'Pioneer',
    0x0157: 'Amazfit', // Anhui Huami
    0x0171: 'Amazon',
    0x018E: 'Google',
    0x01B5: 'Nest',
    0x01DA: 'Logitech',
    0x01DD: 'Philips',
    0x01E0: 'Widex',
    0x01FC: 'Wahoo',
    0x020E: 'Omron',
    0x022B: 'Tesla',
    0x0258: 'Devialet',
    0x027D: 'Huawei',
    0x0282: 'Phonak', // Sonova
    0x0295: 'Signia', // Sivantos
    0x02B2: 'Oura',
    0x02C5: 'Lenovo',
    0x02D5: 'Omron',
    0x02ED: 'HTC',
    0x0304: 'Oura',
    0x0329: 'Eargo',
    0x0381: 'Sharp',
    0x038F: 'Xiaomi',
    0x03FF: 'Withings',
    0x0494: 'Sennheiser',
    0x04AD: 'Shure',
    0x0553: 'Nintendo',
    0x05A7: 'Sonos',
    0x060F: 'Philips Hue',
    0x0618: 'Audio-Technica',
    0x065A: 'Marshall',
    0x067C: 'Tile',
    0x068E: 'Razer',
    0x072F: 'OnePlus',
    0x075A: 'Harman',
    0x079A: 'OPPO',
    0x07C9: 'Skullcandy',
    0x07E0: 'Edifier',
    0x07FA: 'Klipsch',
    0x0837: 'vivo',
    0x08A4: 'realme',
    0x08C3: 'Chipolo',
    0x09C6: 'HONOR',
    0x0A12: 'Dyson',
    0x0A2A: 'Yamaha',
    0x0A82: 'Corsair',
    0x0BA3: 'Sennheiser', // Sonova Consumer Hearing
    0x0BC6: 'TCL',
    0x0CAC: 'Shokz',
    0x0CC2: 'Anker', // soundcore / eufy
    0x0CCB: 'Nothing',
    0x0CE9: 'JLab',
    0x0D10: 'JVC Kenwood',
    0x0D81: 'beyerdynamic',
    0x0E41: 'ASUS',
    0x0E66: 'Baseus',
    0x0FA6: 'UGREEN',
  };

  // --------------------------------------------------------------------
  // Apple proximity pairing
  // --------------------------------------------------------------------

  /// Model behind an Apple proximity-pairing id, or `null` when unrecognised.
  ///
  /// ⚠️ These ids are **not published by Apple**; they are the community
  /// mapping every AirPods battery widget uses. They are the only way to put a
  /// real product name on a pair of AirPods, which advertise anonymously while
  /// they sit in a closed case — precisely the moment this app is useful. The
  /// table is deliberately limited to the models with broad agreement across
  /// sources; anything else degrades to "Apple earbuds", never to a wrong name.
  ///
  /// The battery levels in the same payload are *not* read: Apple encrypts part
  /// of that record on recent firmware, and a wrong battery figure is worse
  /// than none. Battery only ever comes from the standard Battery Service.
  static KnownModel? appleModel(int modelId) => _appleModels[modelId];

  static const Map<int, KnownModel> _appleModels = <int, KnownModel>{
    // Product names are proper nouns, so they are never translated. The
    // numbered forms are used instead of Apple's "(2nd generation)" wording
    // precisely because they read the same in every locale.
    0x2002: (name: 'AirPods', category: DeviceCategory.earbuds),
    0x200F: (name: 'AirPods 2', category: DeviceCategory.earbuds),
    0x2013: (name: 'AirPods 3', category: DeviceCategory.earbuds),
    0x200E: (name: 'AirPods Pro', category: DeviceCategory.earbuds),
    0x2014: (name: 'AirPods Pro 2', category: DeviceCategory.earbuds),
    0x200A: (name: 'AirPods Max', category: DeviceCategory.headphones),
    0x200D: (name: 'Powerbeats Pro', category: DeviceCategory.earbuds),
  };

  // --------------------------------------------------------------------
  // GAP appearance
  // --------------------------------------------------------------------

  /// Maps the 16-bit GAP appearance onto a category.
  ///
  /// Layout is fixed by the SIG: the top 10 bits are the category and the low 6
  /// the subcategory.
  static DeviceCategory categoryForAppearance(int appearance) {
    final int category = (appearance >> 6) & 0x3FF;
    final int subcategory = appearance & 0x3F;

    return switch (category) {
      0x001 => DeviceCategory.phone,
      // Subcategory 0x07 is "Tablet"; everything else in the computer family
      // reads as a computer to a user hunting for a lost device.
      0x002 =>
        subcategory == 0x07 ? DeviceCategory.tablet : DeviceCategory.computer,
      0x003 || 0x004 => DeviceCategory.watch,
      0x005 || 0x027 || 0x028 => DeviceCategory.tv,
      0x008 || 0x009 => DeviceCategory.tracker, // Tag / Keyring
      0x00C ||
      0x00D ||
      0x00E ||
      0x010 ||
      0x031 ||
      0x032 => DeviceCategory.healthSensor,
      0x00F => switch (subcategory) {
        0x01 => DeviceCategory.keyboard,
        0x02 || 0x09 => DeviceCategory.mouse, // Mouse / Touchpad
        0x03 || 0x04 => DeviceCategory.gamepad, // Joystick / Gamepad
        _ => DeviceCategory.unknown,
      },
      0x011 || 0x012 => DeviceCategory.fitnessBand,
      // Control devices, sensors, lighting, HVAC, blinds, appliances: all the
      // fixed hardware around a home. One bucket — the user is not hunting for
      // their thermostat, they just need it to not look like their earbuds.
      0x013 ||
      0x014 ||
      0x015 ||
      0x016 ||
      0x017 ||
      0x018 ||
      0x019 ||
      0x01A ||
      0x01B ||
      0x01C ||
      0x01F ||
      0x020 ||
      0x024 => DeviceCategory.smartHome,
      0x021 => DeviceCategory.speaker, // Audio Sink
      0x023 => DeviceCategory.carKit, // Motorized Vehicle
      // Wearable Audio Device. Subcategories 1/5/6 are the earbud variants,
      // 2/3/4 the headset, headphones and neck band.
      0x025 => switch (subcategory) {
        0x01 || 0x05 || 0x06 => DeviceCategory.earbuds,
        _ => DeviceCategory.headphones,
      },
      0x029 => DeviceCategory.hearingAid,
      _ => DeviceCategory.unknown,
    };
  }

  // --------------------------------------------------------------------
  // Service UUIDs
  // --------------------------------------------------------------------

  /// Category implied by the advertised services, most specific test first.
  static DeviceCategory categoryForServices(Set<int> uuids) {
    if (uuids.contains(hearingAccess)) return DeviceCategory.hearingAid;
    if (uuids.any(_tile.contains)) return DeviceCategory.tracker;
    if (uuids.contains(eddystone) || uuids.contains(exposureNotification)) {
      return DeviceCategory.beacon;
    }
    // The classic Proximity profile — "beep when I ask" plus "shout when we
    // drift apart" — is what a key finder advertises.
    if (uuids.contains(immediateAlert) && uuids.contains(linkLoss)) {
      return DeviceCategory.tracker;
    }
    if (uuids.any(_health.contains)) return DeviceCategory.healthSensor;
    if (uuids.any(_fitness.contains)) return DeviceCategory.fitnessBand;
    // LE Audio without the Hearing Access Service above: something worn on the
    // head. Speakers advertise an appearance, which outranks this.
    if (uuids.any(_leAudio.contains)) return DeviceCategory.headphones;
    return DeviceCategory.unknown;
  }

  static Set<DeviceTrait> traitsForServices(Set<int> uuids) {
    return <DeviceTrait>{
      if (uuids.contains(fastPair)) DeviceTrait.fastPair,
      if (uuids.contains(hearingAccess)) DeviceTrait.hearingAid,
      if (uuids.any(_leAudio.contains)) DeviceTrait.leAudio,
      if (uuids.contains(eddystone) || uuids.contains(exposureNotification))
        DeviceTrait.beacon,
    };
  }

  // --------------------------------------------------------------------
  // Advertised name
  // --------------------------------------------------------------------

  /// Last-resort category guess from the advertised name.
  ///
  /// Only runs when the standards-based sources came up empty, and only on
  /// keywords distinctive enough not to fire on someone's name — "car" is out
  /// (it matches "Carlos"), "carplay" is in.
  static DeviceCategory categoryForName(String name) {
    if (name.isEmpty) return DeviceCategory.unknown;
    final String folded = foldForMatching(name);

    for (final MapEntry<DeviceCategory, List<String>> entry
        in _nameKeywords.entries) {
      for (final String keyword in entry.value) {
        if (folded.contains(keyword)) return entry.key;
      }
    }
    return DeviceCategory.unknown;
  }

  /// Lowercases and strips the Spanish accents, so "Ratón" matches "raton".
  static String foldForMatching(String value) {
    const Map<String, String> accents = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    final StringBuffer buffer = StringBuffer();
    for (final String character in value.toLowerCase().split('')) {
      buffer.write(accents[character] ?? character);
    }
    return buffer.toString();
  }

  /// Iteration order is the match order, so the specific buckets (trackers,
  /// earbuds) get first refusal over the broad ones.
  static const Map<DeviceCategory, List<String>> _nameKeywords =
      <DeviceCategory, List<String>>{
        DeviceCategory.tracker: <String>[
          'airtag',
          'smarttag',
          'chipolo',
          'tile ',
          'localizador',
        ],
        DeviceCategory.earbuds: <String>[
          'airpods',
          'buds',
          'earbud',
          'pods',
          'tws',
          'in-ear',
        ],
        DeviceCategory.headphones: <String>[
          'headphone',
          'headset',
          'auricular',
          'audifono',
          'cascos',
          'quietcomfort',
          'beats',
          'wh-1000',
        ],
        DeviceCategory.speaker: <String>[
          'speaker',
          'altavoz',
          'soundbar',
          'barra de sonido',
          'homepod',
          'sonos',
        ],
        DeviceCategory.watch: <String>['watch', 'reloj'],
        DeviceCategory.fitnessBand: <String>[
          'mi band',
          'smart band',
          'fitbit',
          'pulsera',
        ],
        DeviceCategory.gamepad: <String>[
          'gamepad',
          'dualsense',
          'dualshock',
          'joy-con',
          'xbox',
          'mando',
        ],
        DeviceCategory.keyboard: <String>['keyboard', 'teclado'],
        DeviceCategory.mouse: <String>['mouse', 'raton'],
        DeviceCategory.tablet: <String>['ipad', 'tablet'],
        DeviceCategory.computer: <String>[
          'macbook',
          'laptop',
          'imac',
          'portatil',
        ],
        DeviceCategory.phone: <String>['iphone', 'telefono', 'movil'],
        DeviceCategory.tv: <String>[
          'chromecast',
          'fire tv',
          'roku',
          'televis',
          'smart tv',
        ],
        DeviceCategory.carKit: <String>['carplay', 'car kit', 'carkit'],
      };
}
