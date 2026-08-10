import 'package:app_template/core/extensions/build_context_x.dart';
import 'package:app_template/core/theme/app_spacing.dart';
import 'package:app_template/core/widgets/permission_dialogs.dart';
import 'package:app_template/core/widgets/section_card.dart';
import 'package:app_template/services/permissions/permission_providers.dart';
import 'package:app_template/services/permissions/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demonstrates the permission flow for the three groups a typical Android app
/// needs. Each request is triggered by an explicit user tap — never at startup,
/// which is both a UX rule and a Play policy expectation.
class PermissionsCard extends ConsumerWidget {
  const PermissionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: context.l10n.permissionsTitle,
      icon: Icons.lock_outline,
      children: <Widget>[
        _PermissionButton(
          icon: Icons.bluetooth,
          label: context.l10n.permissionBluetooth,
          onPressed: () => _requestBluetooth(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PermissionButton(
          icon: Icons.place_outlined,
          label: context.l10n.permissionLocation,
          onPressed: () => _requestSingle(
            context,
            ref,
            permission: AppPermission.location,
            reason: context.l10n.permissionLocationReason,
            name: context.l10n.permissionLocation,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PermissionButton(
          icon: Icons.notifications_none,
          label: context.l10n.permissionNotifications,
          onPressed: () => _requestSingle(
            context,
            ref,
            permission: AppPermission.notifications,
            reason: context.l10n.permissionNotificationsReason,
            name: context.l10n.permissionNotifications,
          ),
        ),
      ],
    );
  }

  Future<void> _requestBluetooth(BuildContext context, WidgetRef ref) async {
    final String name = context.l10n.permissionBluetooth;
    final bool granted = await PermissionFlow.ensureAll(
      context,
      service: ref.read(permissionServiceProvider),
      permissions: <AppPermission>[
        AppPermission.bluetoothScan,
        AppPermission.bluetoothConnect,
      ],
      reason: context.l10n.permissionBluetoothReason,
    );

    if (!context.mounted) return;
    context.showSnack(
      granted
          ? context.l10n.permissionGranted(name)
          : context.l10n.permissionDenied(name),
    );
  }

  Future<void> _requestSingle(
    BuildContext context,
    WidgetRef ref, {
    required AppPermission permission,
    required String reason,
    required String name,
  }) async {
    final bool granted = await PermissionFlow.ensure(
      context,
      service: ref.read(permissionServiceProvider),
      permission: permission,
      reason: reason,
    );

    if (!context.mounted) return;
    context.showSnack(
      granted
          ? context.l10n.permissionGranted(name)
          : context.l10n.permissionDenied(name),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  const _PermissionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
