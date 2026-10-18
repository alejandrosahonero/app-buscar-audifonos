import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/location_services.dart';
import 'package:flutter/material.dart';

/// UI half of [LocationServices], like `PermissionFlow` is for permissions.
abstract final class LocationServicesPrompt {
  /// Returns true when a scan can find something. Otherwise explains why the
  /// list would stay empty and offers the system location settings.
  ///
  /// Returns false even after opening the settings: the user comes back and
  /// taps search again, which re-checks instead of trusting a toggle that may
  /// still be off.
  static Future<bool> ensure(
    BuildContext context, {
    required LocationServices service,
  }) async {
    if (!await service.blocksScan()) return true;
    if (!context.mounted) return false;

    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.finderLocationOffTitle),
        content: Text(dialogContext.l10n.finderLocationOffBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.finderLocationOffAction),
          ),
        ],
      ),
    );
    if (openSettings ?? false) await service.openSettings();
    return false;
  }
}
