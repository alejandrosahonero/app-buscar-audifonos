import 'dart:async';

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/routing/app_routes.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/core/widgets/empty_state.dart';
import 'package:buscar_audifonos/core/widgets/permission_dialogs.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/favorites_controller.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_identity_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_tile.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/favorite_device_tile.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/scan_filter_bar.dart';
import 'package:buscar_audifonos/services/permissions/permission_providers.dart';
import 'package:buscar_audifonos/services/permissions/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The app's main screen: everything the phone can hear, strongest first, with
/// the user's pinned devices held above it.
///
/// Built on [BaseScreen], so the anchored adaptive banner sits below the list
/// and below the scan button (never over either) and disappears for premium
/// users. A list screen is exactly the placement the project guide allows a
/// banner on.
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
    final List<DiscoveredDevice> unpinned = ref.watch(unpinnedDevicesProvider);
    final List<FavoriteDevice> favorites = ref.watch(favoriteDevicesProvider);
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
            child: _ScannerList(
              favorites: favorites,
              devices: unpinned,
              isScanning: isScanning,
              onOpen: _openRadar,
              onUnpin: _confirmUnpin,
              onRename: _renameFavorite,
            ),
          ),
        ],
      ),
    );
  }

  void _openRadar(String deviceId) {
    context.pushNamed(
      AppRoutes.radarName,
      pathParameters: <String, String>{AppRoutes.radarDeviceIdParam: deviceId},
    );
  }

  /// Lets the user name a favourite whatever they call it out loud.
  ///
  /// Two earbuds of the same model advertise the same string, so the advertised
  /// name is exactly what fails to tell them apart. Free, and reversible by
  /// emptying the field.
  Future<void> _renameFavorite(FavoriteDevice favorite) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _RenameDialog(favorite: favorite),
    );

    // `null` is a cancel; the empty string is "go back to the advertised name".
    if (name == null || !mounted) return;
    await ref
        .read(favoriteDevicesProvider.notifier)
        .rename(favorite.id, name.isEmpty ? null : name);
    if (!mounted) return;
    context.showSnack(context.l10n.finderRenamed);
  }

  /// Unpinning is free, but it costs a rewarded video to undo, so it always
  /// asks first.
  Future<void> _confirmUnpin(FavoriteDevice favorite) async {
    final String name = deviceDisplayName(
      context,
      favorite.identity,
      customName: favorite.customName,
    );
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.finderFavoriteRemoveTitle),
        content: Text(dialogContext.l10n.finderFavoriteRemoveBody(name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.commonRemove),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(favoriteDevicesProvider.notifier).remove(favorite.id);
    if (!mounted) return;
    context.showSnack(context.l10n.finderFavoriteRemoved);
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

/// Asks for the new name of a favourite.
///
/// Stateful for one reason: a [TextEditingController] has to be disposed, and a
/// dialog built inline in a callback has nowhere to do that.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.favorite});

  final FavoriteDevice favorite;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    // Prefilled with whatever the row reads today, custom or advertised, so the
    // user edits a name instead of inventing one from scratch.
    text: deviceDisplayName(
      context,
      widget.favorite.identity,
      customName: widget.favorite.customName,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.finderRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        // A device name is one short line: the keyboard's action key should
        // finish the job, not add a second line to it.
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        maxLength: 40,
        decoration: InputDecoration(
          labelText: context.l10n.finderRenameFieldLabel,
          helperText: context.l10n.finderRenameHelp,
          helperMaxLines: 2,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.finderRenameSave),
        ),
      ],
    );
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

/// Favourites on top, everything the scan can hear below them.
///
/// One scroll view rather than two stacked lists: the favourites section is
/// usually two or three rows, and giving it a box of its own would either waste
/// height when it is short or fight the main list for it when it is long.
class _ScannerList extends StatelessWidget {
  const _ScannerList({
    required this.favorites,
    required this.devices,
    required this.isScanning,
    required this.onOpen,
    required this.onUnpin,
    required this.onRename,
  });

  final List<FavoriteDevice> favorites;
  final List<DiscoveredDevice> devices;
  final bool isScanning;
  final void Function(String deviceId) onOpen;
  final void Function(FavoriteDevice favorite) onUnpin;
  final void Function(FavoriteDevice favorite) onRename;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        if (favorites.isNotEmpty) ...<Widget>[
          _SectionHeader(title: context.l10n.finderFavoritesTitle),
          // `.builder`, never a fixed children list: this one is short, but the
          // rule keeps applying as the user pins more devices.
          SliverList.builder(
            itemCount: favorites.length,
            itemBuilder: (BuildContext context, int index) {
              final FavoriteDevice favorite = favorites[index];
              return FavoriteDeviceTile(
                key: ValueKey<String>(favorite.id),
                favorite: favorite,
                onTap: () => onOpen(favorite.id),
                onLongPress: () => onUnpin(favorite),
                onRename: () => onRename(favorite),
              );
            },
          ),
          const SliverToBoxAdapter(child: Divider(height: AppSpacing.lg)),
          _SectionHeader(title: context.l10n.finderOtherDevicesTitle),
        ],
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: isScanning ? Icons.radar : Icons.bluetooth_searching,
              title: isScanning
                  ? context.l10n.finderScanningTitle
                  : context.l10n.finderEmptyTitle,
              // Nothing under the title before the first scan: the title is
              // already the whole call to action.
              message: isScanning ? context.l10n.finderScanningMessage : null,
            ),
          )
        else
          SliverPadding(
            // Clears the floating button from the last row.
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
            // A busy room easily produces a hundred advertisers, so the rows
            // are built lazily.
            sliver: SliverList.builder(
              itemCount: devices.length,
              itemBuilder: (BuildContext context, int index) {
                final DiscoveredDevice device = devices[index];
                return DeviceTile(
                  // Keyed by id so the tiles follow their device as the list
                  // re-sorts by signal strength instead of animating through
                  // each other.
                  key: ValueKey<String>(device.id),
                  identity: device.identity,
                  device: device,
                  onTap: () => onOpen(device.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(
          title,
          style: context.texts.labelLarge?.copyWith(
            color: context.colors.primary,
          ),
        ),
      ),
    );
  }
}
