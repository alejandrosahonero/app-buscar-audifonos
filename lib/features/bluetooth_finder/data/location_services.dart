import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:flutter/services.dart';

/// The phone's location toggle, as far as Bluetooth scanning cares about it.
///
/// Up to Android 11 the system delivers no BLE results while location is off:
/// the scan starts fine and finds nothing, which looks exactly like a broken
/// app. Android 12+ scans without it. Talks to `LocationServices.kt`; pure
/// logic, no `BuildContext` — the prompt lives in `LocationServicesPrompt`.
class LocationServices {
  const LocationServices();

  static const MethodChannel _channel = MethodChannel(
    'buscaraudifonos/location_services',
  );

  /// Whether a scan right now would come back empty because location is off.
  ///
  /// Any channel failure answers `false`: a missing check must never stand
  /// between the user and a scan that may well work.
  Future<bool> blocksScan() async {
    try {
      final bool required =
          await _channel.invokeMethod<bool>('isRequiredForScan') ?? false;
      if (!required) return false;
      final bool enabled =
          await _channel.invokeMethod<bool>('isEnabled') ?? true;
      return !enabled;
    } on MissingPluginException {
      return false; // Not Android, or a test host.
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Location services check failed',
        name: 'bluetooth',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Opens the system location settings. `false` if no screen could be shown.
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }
}
