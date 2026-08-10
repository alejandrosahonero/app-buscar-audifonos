import 'package:app_template/core/extensions/build_context_x.dart';
import 'package:app_template/services/permissions/permission_service.dart';
import 'package:flutter/material.dart';

/// UI half of the permission flow.
///
/// Kept separate from [PermissionService] so the service has no `BuildContext`
/// dependency. Use [PermissionFlow.ensure] from a screen: it explains, asks,
/// and routes the user to the settings screen when the permission is blocked.
abstract final class PermissionFlow {
  /// Requests [permission], showing a rationale first when the OS says the user
  /// already denied it once, and offering "open settings" when it is
  /// permanently denied.
  ///
  /// Returns true when the app ends up holding the permission.
  static Future<bool> ensure(
    BuildContext context, {
    required PermissionService service,
    required AppPermission permission,
    required String reason,
  }) async {
    PermissionOutcome outcome = await service.check(permission);

    if (outcome == PermissionOutcome.granted ||
        outcome == PermissionOutcome.unsupported) {
      return true;
    }

    if (outcome == PermissionOutcome.denied &&
        await service.shouldShowRationale(permission)) {
      if (!context.mounted) return false;
      final bool accepted = await _showRationale(context, reason: reason);
      if (!accepted) return false;
    }

    outcome = await service.request(permission);

    if (outcome == PermissionOutcome.permanentlyDenied) {
      if (!context.mounted) return false;
      final bool goToSettings = await _showBlocked(context);
      if (goToSettings) await service.openSettings();
      return false;
    }

    return outcome == PermissionOutcome.granted ||
        outcome == PermissionOutcome.unsupported;
  }

  /// Same as [ensure] but for a group of permissions that belong together
  /// (Bluetooth scan + connect). One rationale, one system prompt sequence.
  ///
  /// Returns true only when every permission in the group ends up granted.
  static Future<bool> ensureAll(
    BuildContext context, {
    required PermissionService service,
    required List<AppPermission> permissions,
    required String reason,
  }) async {
    bool allGranted = true;
    bool anyMissing = false;

    for (final AppPermission permission in permissions) {
      final PermissionOutcome outcome = await service.check(permission);
      if (outcome != PermissionOutcome.granted &&
          outcome != PermissionOutcome.unsupported) {
        anyMissing = true;
      }
    }
    if (!anyMissing) return true;

    if (!context.mounted) return false;
    if (!await _showRationale(context, reason: reason)) return false;

    final Map<AppPermission, PermissionOutcome> results = await service
        .requestAll(permissions);

    bool blocked = false;
    for (final PermissionOutcome outcome in results.values) {
      if (outcome == PermissionOutcome.permanentlyDenied) blocked = true;
      if (outcome != PermissionOutcome.granted &&
          outcome != PermissionOutcome.unsupported) {
        allGranted = false;
      }
    }

    if (blocked) {
      if (!context.mounted) return false;
      if (await _showBlocked(context)) await service.openSettings();
    }

    return allGranted;
  }

  static Future<bool> _showRationale(
    BuildContext context, {
    required String reason,
  }) async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.permissionRationaleTitle),
        content: Text(reason),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.commonContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  static Future<bool> _showBlocked(BuildContext context) async {
    final bool? goToSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.permissionDeniedForeverTitle),
        content: Text(dialogContext.l10n.permissionDeniedForeverBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.permissionOpenSettings),
          ),
        ],
      ),
    );
    return goToSettings ?? false;
  }
}
