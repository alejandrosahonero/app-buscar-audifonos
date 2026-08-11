/// Route paths and names.
///
/// Never type a path literal at a call site: use these constants so a rename is
/// a single edit and deep links stay consistent with the Android intent filter
/// declared in `AndroidManifest.xml`.
abstract final class AppRoutes {
  static const String homePath = '/';
  static const String homeName = 'home';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// Paywall. Reachable by deep link so a campaign can land directly on it.
  static const String paywallPath = '/premium';
  static const String paywallName = 'premium';

  /// Proximity radar for one device. The id travels in the path (MAC address on
  /// Android, system UUID on iOS) so the screen survives a rebuild and can be
  /// reached from a notification.
  static const String radarPath = '/radar/:deviceId';
  static const String radarName = 'radar';
  static const String radarDeviceIdParam = 'deviceId';
}
