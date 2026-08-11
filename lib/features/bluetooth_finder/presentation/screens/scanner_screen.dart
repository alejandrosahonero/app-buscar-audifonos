import 'dart:async';

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/routing/app_routes.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/core/widgets/empty_state.dart';
import 'package:buscar_audifonos/core/widgets/permission_dialogs.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_tile.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/scan_filter_bar.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/permissions/permission_providers.dart';
import 'package:buscar_audifonos/services/permissions/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The app's main screen: everything the phone can hear, strongest first.
///
/// Built on [BaseScreen], so the anchored adaptive banner sits below the list
/// (never over it) and disappears for premium users. A list screen is exactly
/// the placement the project guide allows a banner on.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  AppLifecycleListener? _lifecycle;
  bool _resumeScanOnReturn = false;

  @override
  void initState() {
    super.initState();
    // A BLE scan at `lowLatency` is one of the most expensive things an app can
    // do to a battery. Nothing scans while the app is not in front of the user.
    _lifecycle = AppLifecycleListener(
      onPause: _pauseScan,
      onResume: _resumeScan,
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _pauseScan() {
    final BluetoothScanService service = ref.read(bluetoothScanServiceProvider);
    _resumeScanOnReturn = service.isScanningNow;
    if (_resumeScanOnReturn) unawaited(service.stop());
  }

  void _resumeScan() {
    if (!_resumeScanOnReturn) return;
    _resumeScanOnReturn = false;
    unawaited(ref.read(bluetoothScanServiceProvider).start());
  }

  @override
  Widget build(BuildContext context) {
    final bool isScanning = ref.watch(isScanningProvider).value ?? false;
    final List<DiscoveredDevice> visible = ref.watch(visibleDevicesProvider);
    final int total = ref.watch(discoveredDevicesProvider).value?.length ?? 0;

    return BaseScreen(
      title: context.l10n.appTitle,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.goNamed(AppRoutes.settingsName),
          icon: const Icon(Icons.settings_outlined),
          tooltip: context.l10n.settingsTitle,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _toggleScan(isScanning: isScanning),
        icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(
          isScanning
              ? context.l10n.finderScanStop
              : context.l10n.finderScanStart,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _AdapterBanner(),
          ScanFilterBar(hiddenCount: total - visible.length),
          Expanded(
            child: _DeviceList(devices: visible, isScanning: isScanning),
          ),
          if (!ref.watch(isPremiumProvider)) const _RemoveAdsEntryPoint(),
        ],
      ),
    );
  }

  Future<void> _toggleScan({required bool isScanning}) async {
    final BluetoothScanService service = ref.read(bluetoothScanServiceProvider);

    if (isScanning) {
      await service.stop();
      return;
    }

    // Permissions are requested here — after an explicit tap — and never at
    // startup. Scan + connect + location travel as one group so the user sees a
    // single rationale and a single system sequence.
    final bool granted = await PermissionFlow.ensureAll(
      context,
      service: ref.read(permissionServiceProvider),
      permissions: const <AppPermission>[
        AppPermission.bluetoothScan,
        AppPermission.bluetoothConnect,
        AppPermission.location,
      ],
      reason: context.l10n.finderPermissionReason,
    );

    if (!mounted) return;
    if (!granted) {
      context.showSnack(context.l10n.finderPermissionRequired);
      return;
    }

    await service.start();
  }
}

/// Warns about the radio being off or missing. Renders nothing when everything
/// is fine, so the list keeps the full height in the normal case.
class _AdapterBanner extends ConsumerWidget {
  const _AdapterBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BluetoothAvailability availability =
        ref.watch(bluetoothAvailabilityProvider).value ??
        BluetoothAvailability.unknown;

    return switch (availability) {
      BluetoothAvailability.ready ||
      BluetoothAvailability.unknown => const SizedBox.shrink(),
      BluetoothAvailability.off => _Notice(
        icon: Icons.bluetooth_disabled,
        message: context.l10n.finderBluetoothOff,
        action: TextButton(
          onPressed: () =>
              ref.read(bluetoothScanServiceProvider).requestEnable(),
          child: Text(context.l10n.finderBluetoothTurnOn),
        ),
      ),
      BluetoothAvailability.unauthorized => _Notice(
        icon: Icons.lock_outline,
        message: context.l10n.finderPermissionRequired,
        action: TextButton(
          onPressed: () => ref.read(permissionServiceProvider).openSettings(),
          child: Text(context.l10n.permissionOpenSettings),
        ),
      ),
      BluetoothAvailability.unsupported => _Notice(
        icon: Icons.error_outline,
        message: context.l10n.finderBluetoothUnsupported,
      ),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: context.colors.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSecondaryContainer,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.isScanning});

  final List<DiscoveredDevice> devices;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return EmptyState(
        icon: isScanning ? Icons.radar : Icons.bluetooth_searching,
        title: isScanning
            ? context.l10n.finderScanningTitle
            : context.l10n.finderEmptyTitle,
        message: isScanning
            ? context.l10n.finderScanningMessage
            : context.l10n.finderEmptyMessage,
      );
    }

    // `.builder`, never a `ListView(children: [...])`: a busy room easily
    // produces a hundred advertisers.
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl + AppSpacing.lg),
      itemCount: devices.length,
      itemBuilder: (BuildContext context, int index) {
        final DiscoveredDevice device = devices[index];
        return DeviceTile(
          // Keyed by id so the tiles follow their device as the list re-sorts
          // by signal strength instead of animating through each other.
          key: ValueKey<String>(device.id),
          device: device,
          onTap: () => context.pushNamed(
            AppRoutes.radarName,
            pathParameters: <String, String>{
              AppRoutes.radarDeviceIdParam: device.id,
            },
          ),
        );
      },
    );
  }
}

/// Discreet paywall entry point, after the content and never blocking.
class _RemoveAdsEntryPoint extends StatelessWidget {
  const _RemoveAdsEntryPoint();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.goNamed(AppRoutes.paywallName),
      icon: const Icon(Icons.block),
      label: Text(context.l10n.settingsRemoveAds),
    );
  }
}
