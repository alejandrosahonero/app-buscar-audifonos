import 'package:app_template/core/utils/app_logger.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permissions this template knows how to ask for.
///
/// Using an app-level enum instead of the plugin's `Permission` keeps the
/// plugin out of the UI layer and forces every new permission to be added
/// consciously — an unused permission in the manifest is a Play rejection risk.
enum AppPermission {
  /// Android 12+ `BLUETOOTH_SCAN`. On older versions the legacy `BLUETOOTH`
  /// permission is granted at install time.
  bluetoothScan,

  /// Android 12+ `BLUETOOTH_CONNECT`.
  bluetoothConnect,

  /// `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` while in use.
  /// Background location is intentionally NOT included: it requires a separate
  /// Play Console review.
  location,

  /// Android 13+ `POST_NOTIFICATIONS`.
  notifications,
}

/// Normalized result of a permission check or request.
enum PermissionOutcome {
  granted,

  /// Denied this time. Asking again later is allowed.
  denied,

  /// Denied with "don't ask again", or blocked by policy. The only way out is
  /// the system settings screen.
  permanentlyDenied,

  /// Not applicable on this OS version (e.g. POST_NOTIFICATIONS below
  /// Android 13). Treat it as "granted" for flow purposes.
  unsupported,
}

/// Runtime permission handling.
///
/// This class is pure logic and has no UI: the rationale and "open settings"
/// dialogs live in `core/widgets/permission_dialogs.dart`, so the service stays
/// testable and can be called from background code.
class PermissionService {
  const PermissionService();

  Permission _map(AppPermission permission) => switch (permission) {
    AppPermission.bluetoothScan => Permission.bluetoothScan,
    AppPermission.bluetoothConnect => Permission.bluetoothConnect,
    AppPermission.location => Permission.locationWhenInUse,
    AppPermission.notifications => Permission.notification,
  };

  PermissionOutcome _toOutcome(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return PermissionOutcome.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }

  /// Current status without prompting the user. Use it to render state (a
  /// toggle, a checklist) and to decide whether a rationale is needed.
  Future<PermissionOutcome> check(AppPermission permission) async {
    try {
      return _toOutcome(await _map(permission).status);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Permission check failed for $permission',
        name: 'permissions',
        error: error,
        stackTrace: stackTrace,
      );
      return PermissionOutcome.unsupported;
    }
  }

  /// Shows the system dialog. Call it only right after the user tapped
  /// something that clearly needs the permission — never at startup.
  Future<PermissionOutcome> request(AppPermission permission) async {
    try {
      return _toOutcome(await _map(permission).request());
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Permission request failed for $permission',
        name: 'permissions',
        error: error,
        stackTrace: stackTrace,
      );
      return PermissionOutcome.unsupported;
    }
  }

  /// Requests several permissions in one system dialog sequence.
  ///
  /// Bluetooth scan + connect belong together: asking for them separately
  /// produces two dialogs in a row, which measurably increases the denial rate.
  Future<Map<AppPermission, PermissionOutcome>> requestAll(
    List<AppPermission> permissions,
  ) async {
    try {
      final Map<Permission, PermissionStatus> statuses = await permissions
          .map(_map)
          .toList()
          .request();

      return <AppPermission, PermissionOutcome>{
        for (final AppPermission permission in permissions)
          permission: _toOutcome(
            statuses[_map(permission)] ?? PermissionStatus.denied,
          ),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Bulk permission request failed',
        name: 'permissions',
        error: error,
        stackTrace: stackTrace,
      );
      return <AppPermission, PermissionOutcome>{
        for (final AppPermission permission in permissions)
          permission: PermissionOutcome.unsupported,
      };
    }
  }

  /// Whether the OS wants us to explain why we need the permission before the
  /// system dialog (i.e. the user already denied it once).
  Future<bool> shouldShowRationale(AppPermission permission) =>
      _map(permission).shouldShowRequestRationale;

  /// Opens the app's settings page. The only recovery path from
  /// [PermissionOutcome.permanentlyDenied].
  Future<bool> openSettings() => openAppSettings();
}
