/// What a scanned advertiser *is*, as far as its advertisement can tell.
///
/// Deliberately coarse: the list needs a recognizable icon and a human noun,
/// not a product database. Anything the packet does not pin down stays
/// [DeviceCategory.unknown] rather than being guessed into the wrong bucket —
/// a wrong icon is worse than a neutral one.
enum DeviceCategory {
  earbuds,
  headphones,
  speaker,
  hearingAid,
  watch,
  fitnessBand,
  phone,
  computer,
  tablet,
  tv,
  keyboard,
  mouse,
  gamepad,
  tracker,
  beacon,
  healthSensor,
  carKit,
  smartHome,
  unknown,
}

/// Extra capabilities worth surfacing next to a device.
///
/// Only traits that answer "is this the thing I am looking for?" make the cut.
/// Anything that resolves to a long opaque number (addresses, rotating
/// identifiers, raw payloads) is intentionally absent: it is not actionable and
/// it is exactly the kind of data a finder app has no business displaying.
enum DeviceTrait {
  /// Google Fast Pair. Overwhelmingly headphones, earbuds and trackers.
  fastPair,

  /// Microsoft Swift Pair — a Windows accessory announcing itself for pairing.
  swiftPair,

  /// Broadcasting on Apple's Find My network (AirTag, or a lost Apple device).
  findMy,

  /// Bluetooth LE Audio acceptor (Auracast-era earbuds, hearing aids).
  leAudio,

  /// Implements the Hearing Access Service — a real hearing aid.
  hearingAid,

  /// A stationary transmitter (iBeacon / Eddystone). Never the lost earbud.
  beacon,
}
