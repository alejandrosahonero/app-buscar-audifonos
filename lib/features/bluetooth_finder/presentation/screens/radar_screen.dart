import 'dart:async';

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/core/widgets/permission_dialogs.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/bluetooth_scan_service.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/geiger_sounder.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/favorites_controller.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_identity_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/radar_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:buscar_audifonos/services/ads/ads_providers.dart';
import 'package:buscar_audifonos/services/ads/ads_service.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/permissions/permission_providers.dart';
import 'package:buscar_audifonos/services/permissions/permission_service.dart';
import 'package:buscar_audifonos/services/review/review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// What is behind the reading the radar is holding.
enum _RadarBacking {
  /// A scan is running: the stream is the truth and the radar follows it.
  live,

  /// The scan was stopped when this screen opened and is being restarted. What
  /// the stream still holds is the last packet from before Stop.
  restarting,

  /// No scan could be started (permissions refused, radio off). Nothing here
  /// can update, so nothing here is shown as a reading.
  noScan,
}

/// Live proximity radar for one device.
///
/// The screen reads the device straight off the scan stream (by id) rather than
/// receiving a snapshot through the route: the whole point is that the reading
/// keeps changing while the user walks around.
///
/// `showBanner: false` on purpose — the guide reserves banners for list and
/// consultation screens, and this one has a full-width control row at the
/// bottom edge that a banner would sit next to.
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({required this.deviceId, super.key});

  final String deviceId;

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  final GeigerSounder _sounder = GeigerSounder();

  /// Held in a field rather than read from `ref` in [dispose]: stopping the
  /// scan on the way out has to work for the system back gesture too, and by
  /// then reading a provider is no longer allowed.
  late final BluetoothScanService _scanService = ref.read(
    bluetoothScanServiceProvider,
  );

  /// Whether there is a scan running behind this screen right now.
  ///
  /// The stream keeps serving the last packet of a stopped scan — that is what
  /// keeps the list from blanking — so the radar has to know whether what it is
  /// holding is a reading or a photograph.
  _RadarBacking _backing = _RadarBacking.live;

  /// Set when this screen is what turned the scan back on, so leaving restores
  /// the user's choice instead of quietly draining the battery.
  bool _stopScanOnLeave = false;

  /// Description captured on entry, so the header does not go blank the moment
  /// the device stops advertising — which is exactly when the user is staring
  /// at this screen hardest.
  DeviceIdentity? _lastKnownIdentity;
  bool _lastKnownPaired = false;

  /// The device was last heard through Bluetooth classic. Its first answer
  /// after a scan restart can take a whole inquiry (~12 s), so for a while its
  /// absence means "still listening", not "switched off".
  bool _lastKnownSlow = false;
  bool _slowGraceActive = false;
  Timer? _slowGraceTimer;
  bool _soundOn = false;
  bool _reviewRequested = false;

  @override
  void initState() {
    super.initState();

    // `ref.listen` (below) only fires on *changes*, so seed from whatever the
    // scan already knows about this device — or, when it knows nothing because
    // the device is a favourite that is out of range, from what was saved when
    // the user pinned it.
    final DiscoveredDevice? current = ref.read(
      deviceByIdProvider(widget.deviceId),
    );
    _lastKnownIdentity = current?.identity ?? _savedIdentity();
    _lastKnownPaired = current?.isPaired ?? false;
    _lastKnownSlow = current?.isSlowSignal ?? _savedIsClassic();

    // Tells the scanner which device matters: classic discovery competes with
    // BLE for the radio and is paused while a BLE device is being followed.
    _scanService.focusOn(widget.deviceId);

    // Decided before the first frame: with the scan stopped, `current` is the
    // last packet from whenever the user pressed Stop. Its percentage would
    // paint a live-looking radar that never moves again.
    _backing = _scanService.isScanningNow
        ? _RadarBacking.live
        : _RadarBacking.restarting;

    // Off the first frame: loading the audio sources touches the platform.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Scan first: getting a live reading is what the user came for, and it
      // must not queue behind loading an audio asset.
      await _ensureScanning();
      await _sounder.prepare();
      if (!mounted) return;
      final DiscoveredDevice? device = ref.read(
        deviceByIdProvider(widget.deviceId),
      );
      if (device != null) _sounder.updateCloseness(device.closeness);
    });
  }

  @override
  void dispose() {
    // Covers both exits: the app bar arrow and the system back gesture.
    _slowGraceTimer?.cancel();
    _scanService.focusOn(null);
    if (_stopScanOnLeave) unawaited(_scanService.stop());
    unawaited(_sounder.dispose());
    super.dispose();
  }

  /// Puts a live scan behind this screen, whatever the list was doing.
  ///
  /// Opening a device is a request for a fresh reading of *that* device: a
  /// stopped scan has to be restarted, or the radar is a still photograph.
  /// [BluetoothScanService.start] clears its own cache and emits an empty list,
  /// so the stale reading is gone the moment the scan is running again.
  Future<void> _ensureScanning() async {
    if (_backing != _RadarBacking.restarting) return;

    // Reached with the scan stopped, which includes the cold-start case: a
    // favourite can be opened from the list before anything was ever scanned,
    // so the permissions may still be unanswered. Same grouped sequence the
    // scan button uses.
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
      // Nothing to scan with, so there is nothing to trust either: the readout
      // stays on the no-signal message rather than on a number that can no
      // longer change.
      setState(() => _backing = _RadarBacking.noScan);
      context.showSnack(context.l10n.finderPermissionRequired);
      return;
    }

    _stopScanOnLeave = true;
    await _scanService.start();
    if (!mounted) return;
    setState(
      () => _backing = _scanService.isScanningNow
          ? _RadarBacking.live
          : _RadarBacking.noScan,
    );
    if (_backing == _RadarBacking.live && _lastKnownSlow) _startSlowGrace();
  }

  /// One full inquiry plus margin. Until then a missing classic device is
  /// reported as "searching", never as "switched off".
  void _startSlowGrace() {
    _slowGraceTimer?.cancel();
    setState(() => _slowGraceActive = true);
    _slowGraceTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slowGraceActive = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Side effects belong in a listener, never in `build`: the sound and the
    // review prompt must fire once per reading, not once per layout pass.
    ref.listen<DiscoveredDevice?>(deviceByIdProvider(widget.deviceId), (
      DiscoveredDevice? previous,
      DiscoveredDevice? next,
    ) {
      // Clicking at the last known closeness would point the user at a device
      // that is not being heard — the audible half of the frozen reading.
      if (next == null || _backing != _RadarBacking.live) {
        _sounder.muted = true;
        return;
      }
      _sounder.muted = !_soundOn;
      _sounder.updateCloseness(next.closeness);
      _rememberIdentity(next);
      _maybeRequestReview(next);
    });

    final DiscoveredDevice? live = ref.watch(
      deviceByIdProvider(widget.deviceId),
    );
    // Watched unconditionally, then dropped: the subscription must survive the
    // restart, and a reading from a scan that is no longer running is not a
    // reading.
    final DiscoveredDevice? device = _backing == _RadarBacking.live
        ? live
        : null;
    final bool isFavorite = ref.watch(isFavoriteProvider(widget.deviceId));

    final DeviceIdentity identity =
        _lastKnownIdentity ?? DeviceIdentity.unknown;

    return BaseScreen(
      // Watched, not captured: renaming a favourite has to retitle this screen
      // too, or the name the user chose stops being the device's name the
      // moment they open it.
      title: deviceDisplayName(
        context,
        identity,
        customName: ref.watch(favoriteCustomNameProvider(widget.deviceId)),
      ),
      showBanner: false,
      // Only the app bar button runs the "leaving is a value action" path.
      // System back is deliberately left alone so Android's predictive back
      // animation keeps working.
      leading: BackButton(onPressed: _leave),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: <Widget>[
              // Left-aligned like an instrument readout, not centred like a
              // headline.
              _Reading(
                device: device,
                isSearching:
                    _backing == _RadarBacking.restarting ||
                    (_slowGraceActive && device == null),
                identity: identity,
                isPaired: _lastKnownPaired,
                isSlowSignal: _lastKnownSlow,
              ),
              Expanded(
                child: RadarView(
                  closeness: device?.closeness ?? 0,
                  active: device != null,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Readout(
                device: device,
                isSearching:
                    _backing == _RadarBacking.restarting ||
                    (_slowGraceActive && device == null),
              ),
              const SizedBox(height: AppSpacing.md),
              _Controls(
                soundOn: _soundOn,
                isFavorite: isFavorite,
                // Pinning is only offered for a device the scan can actually
                // hear: the saved description is taken from a live reading.
                onFavoritePressed: isFavorite
                    ? _removeFromFavorites
                    : (device == null ? null : () => _addToFavorites(device)),
                onToggleSound: _toggleSound,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps the last resolved description so the header does not go blank the
  /// moment the device stops advertising.
  void _rememberIdentity(DiscoveredDevice device) {
    if (device.identity == _lastKnownIdentity &&
        device.isPaired == _lastKnownPaired &&
        device.isSlowSignal == _lastKnownSlow) {
      return;
    }
    setState(() {
      _lastKnownIdentity = device.identity;
      _lastKnownPaired = device.isPaired;
      _lastKnownSlow = device.isSlowSignal;
    });
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    // Unmuting with nothing on the air would click at the last closeness heard,
    // which is the frozen reading all over again. The listener unmutes as soon
    // as a packet arrives.
    final bool hasSignal =
        _backing == _RadarBacking.live &&
        ref.read(deviceByIdProvider(widget.deviceId)) != null;
    _sounder.muted = !_soundOn || !hasSignal;
  }

  /// The description saved the day this device was pinned, if it ever was.
  ///
  /// This is what keeps the title on a favourite that is switched off: there is
  /// no advertisement left to resolve a name from.
  DeviceIdentity? _savedIdentity() {
    for (final FavoriteDevice favorite in ref.read(favoriteDevicesProvider)) {
      if (favorite.id == widget.deviceId) return favorite.identity;
    }
    return null;
  }

  bool _savedIsClassic() {
    for (final FavoriteDevice favorite in ref.read(favoriteDevicesProvider)) {
      if (favorite.id == widget.deviceId) return favorite.isClassic;
    }
    return false;
  }

  /// Rewarded flow, in the order the project guide mandates:
  /// explain → show → grant only from `onUserEarnedReward` → degrade politely
  /// when there is no inventory.
  Future<void> _addToFavorites(DiscoveredDevice device) async {
    // Premium users bought their way out of ads, so there is no video to offer
    // them and no dialog worth showing.
    if (ref.read(isPremiumProvider)) {
      await _grantFavorite(device);
      return;
    }

    final bool accepted = await _confirmRewarded();
    if (!accepted || !mounted) return;

    final AdShowResult result = await ref
        .read(adsServiceProvider)
        .showRewarded(
          onRewardEarned: (RewardItem _) => unawaited(_grantFavorite(device)),
        );

    if (!mounted) return;

    switch (result) {
      case AdShowResult.shown:
        break;
      // Ads are off for this build or this user: no consent, the SDK has not
      // finished starting up, or the rewarded unit id is not configured at all.
      // There is no video for them to watch, so charging them one would just be
      // a locked door: pin it.
      case AdShowResult.disabled:
        await _grantFavorite(device);
      // Ads are on but the cache is cold. Never dead-end the user for that —
      // say so and let them try again.
      case AdShowResult.notReady:
      case AdShowResult.skipped:
        context.showSnack(context.l10n.rewardsAdUnavailable);
    }
  }

  Future<void> _grantFavorite(DiscoveredDevice device) async {
    await ref.read(favoriteDevicesProvider.notifier).add(device);
    if (!mounted) return;
    context.showSnack(context.l10n.radarFavoriteAdded);
  }

  Future<void> _removeFromFavorites() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.finderFavoriteRemoveTitle),
        content: Text(
          dialogContext.l10n.finderFavoriteRemoveBody(
            deviceDisplayName(
              dialogContext,
              _lastKnownIdentity ?? DeviceIdentity.unknown,
              customName: ref.read(favoriteCustomNameProvider(widget.deviceId)),
            ),
          ),
        ),
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
    await ref.read(favoriteDevicesProvider.notifier).remove(widget.deviceId);
    if (!mounted) return;
    context.showSnack(context.l10n.finderFavoriteRemoved);
  }

  Future<bool> _confirmRewarded() async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.radarFavoriteDialogTitle),
        content: Text(dialogContext.l10n.radarFavoriteDialogBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
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

  /// Reaching arm's reach is this app's success moment — the user found what
  /// they lost. Once per screen, and never after an error.
  void _maybeRequestReview(DiscoveredDevice device) {
    if (_reviewRequested || device.band != ProximityBand.veryNear) return;
    _reviewRequested = true;
    ref.read(reviewServiceProvider).requestReviewAfterSuccess().ignore();
  }

  /// Leaving the radar is a natural transition, which is where the guide allows
  /// an interstitial. The service applies the pacing (N actions AND a minimum
  /// interval); a "no" here is the normal case and must not be worked around.
  Future<void> _leave() async {
    _sounder.muted = true;
    await ref.read(adsServiceProvider).registerActionAndMaybeShowInterstitial();
    if (!mounted) return;
    context.pop();
  }
}

/// The reading, large, then what the device *is*.
///
/// The percentage is set light and big — glanced at while walking, it should
/// read as a calm instrument, not an alarm. Below it, the facts a person can
/// use (kind, brand, battery, whether it is already theirs) where the raw
/// address used to be printed.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.device,
    required this.isSearching,
    required this.identity,
    required this.isPaired,
    required this.isSlowSignal,
  });

  final DiscoveredDevice? device;
  final bool isSearching;
  final DeviceIdentity identity;
  final bool isPaired;
  final bool isSlowSignal;

  @override
  Widget build(BuildContext context) {
    final DiscoveredDevice? device = this.device;
    final String? kind = deviceKindLine(context, identity);
    final Color bandColor = device == null
        ? context.colors.onSurfaceVariant
        : proximityColor(context, device.band);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(
            TextSpan(
              text: device == null ? '—' : '${device.closenessPercent}',
              children: <InlineSpan>[
                TextSpan(
                  text: ' %',
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w300,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            style: context.texts.displayLarge?.copyWith(height: 1),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            device != null
                ? proximityLabel(context, device.band)
                : isSearching
                ? context.l10n.radarSearchingTitle
                : context.l10n.radarSignalLostTitle,
            style: context.texts.titleMedium?.copyWith(
              color: bandColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (kind != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              kind,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          // Room for one more chip than the list: this screen has the width and
          // the user has already committed to this device.
          DeviceMetaChips(
            identity: identity,
            isPaired: isPaired,
            isSlowSignal: isSlowSignal,
            maxChips: 4,
            gapAbove: AppSpacing.sm,
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.device, required this.isSearching});

  final DiscoveredDevice? device;

  /// The scan is being restarted for this screen. Distinguished from "no
  /// signal" because a device that has not been given a chance to answer yet
  /// must not be reported as switched off.
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final DiscoveredDevice? device = this.device;

    // The title ("searching…" / "no signal") already sits under the number;
    // this line only explains it.
    if (device == null) {
      return Text(
        isSearching
            ? context.l10n.radarSearchingMessage
            : context.l10n.radarSignalLostMessage,
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    return Text(
      // A classic device moves in ~12 s steps. Without saying so, walking and
      // seeing nothing change reads as "the app is broken".
      device.isSlowSignal
          ? context.l10n.radarSlowSignalHint
          : context.l10n.radarHint,
      textAlign: TextAlign.center,
      style: context.texts.bodySmall?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.soundOn,
    required this.isFavorite,
    required this.onToggleSound,
    required this.onFavoritePressed,
  });

  final bool soundOn;
  final bool isFavorite;
  final VoidCallback onToggleSound;

  /// `null` disables the button: a device that is not being heard cannot be
  /// pinned, because there is no reading to save a description from.
  final VoidCallback? onFavoritePressed;

  @override
  Widget build(BuildContext context) {
    // Round, icon-first controls with their label underneath: the hands are
    // busy and the eyes are on the room, so the targets are big and few.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _RoundControl(
          icon: soundOn ? Icons.volume_up : Icons.volume_off,
          label: soundOn
              ? context.l10n.radarSoundOn
              : context.l10n.radarSoundOff,
          selected: soundOn,
          onPressed: onToggleSound,
        ),
        const SizedBox(width: AppSpacing.xl),
        _RoundControl(
          icon: isFavorite ? Icons.star : Icons.star_border,
          label: isFavorite
              ? context.l10n.radarFavoriteRemove
              : context.l10n.radarFavoriteAdd,
          selected: isFavorite,
          onPressed: onFavoritePressed,
        ),
      ],
    );
  }
}

/// A 56 dp circle — hairline when off, lit amber when on — with its label below.
class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = IconButton.styleFrom(
      fixedSize: const Size.square(56),
      side: selected ? null : BorderSide(color: context.colors.outlineVariant),
      backgroundColor: selected ? context.colors.primary : Colors.transparent,
      foregroundColor: selected
          ? context.colors.onPrimary
          : context.colors.onSurface,
    );

    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon),
            tooltip: label,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: context.texts.labelMedium?.copyWith(
              color: onPressed == null
                  ? context.colors.outline
                  : context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
