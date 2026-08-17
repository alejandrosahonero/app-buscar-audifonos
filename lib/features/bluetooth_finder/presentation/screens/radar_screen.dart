import 'dart:async';

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/geiger_sounder.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/favorites_controller.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/device_identity_view.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/radar_view.dart';
import 'package:buscar_audifonos/services/ads/ads_providers.dart';
import 'package:buscar_audifonos/services/ads/ads_service.dart';
import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:buscar_audifonos/services/review/review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  /// Description captured on entry, so the header does not go blank the moment
  /// the device stops advertising — which is exactly when the user is staring
  /// at this screen hardest.
  DeviceIdentity? _lastKnownIdentity;
  bool _lastKnownPaired = false;
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

    // Off the first frame: loading the audio sources touches the platform.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _sounder.prepare();
      final DiscoveredDevice? device = ref.read(
        deviceByIdProvider(widget.deviceId),
      );
      if (device != null) _sounder.updateCloseness(device.closeness);
    });
  }

  @override
  void dispose() {
    unawaited(_sounder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Side effects belong in a listener, never in `build`: the sound and the
    // review prompt must fire once per reading, not once per layout pass.
    ref.listen<DiscoveredDevice?>(deviceByIdProvider(widget.deviceId), (
      DiscoveredDevice? previous,
      DiscoveredDevice? next,
    ) {
      if (next == null) return;
      _sounder.updateCloseness(next.closeness);
      _rememberIdentity(next);
      _maybeRequestReview(next);
    });

    final DiscoveredDevice? device = ref.watch(
      deviceByIdProvider(widget.deviceId),
    );
    final bool isFavorite = ref.watch(isFavoriteProvider(widget.deviceId));

    final DeviceIdentity identity =
        _lastKnownIdentity ?? DeviceIdentity.unknown;

    return BaseScreen(
      title: deviceDisplayName(context, identity),
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
              _IdentityHeader(identity: identity, isPaired: _lastKnownPaired),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Center(
                  child: RadarView(
                    closeness: device?.closeness ?? 0,
                    active: device != null,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _Readout(device: device),
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
        device.isPaired == _lastKnownPaired) {
      return;
    }
    setState(() {
      _lastKnownIdentity = device.identity;
      _lastKnownPaired = device.isPaired;
    });
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    _sounder.muted = !_soundOn;
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

/// What the device *is*, under the title.
///
/// This is where the raw address used to be printed. An address identifies
/// hardware and tells a person nothing they can use, so it was replaced by the
/// facts they can: kind, brand, battery, whether it is already theirs.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.identity, required this.isPaired});

  final DeviceIdentity identity;
  final bool isPaired;

  @override
  Widget build(BuildContext context) {
    final String? kind = deviceKindLine(context, identity);

    return Column(
      children: <Widget>[
        if (kind != null)
          Text(
            kind,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        // Room for one more chip than the list: this screen has the width and
        // the user has already committed to this device.
        DeviceMetaChips(
          identity: identity,
          isPaired: isPaired,
          maxChips: 4,
          alignment: WrapAlignment.center,
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.device});

  final DiscoveredDevice? device;

  @override
  Widget build(BuildContext context) {
    final DiscoveredDevice? device = this.device;

    if (device == null) {
      return Column(
        children: <Widget>[
          Text(
            context.l10n.radarSignalLostTitle,
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.radarSignalLostMessage,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Text(
          context.l10n.radarSignalReading(
            device.rssi,
            device.smoothedRssi.round(),
          ),
          style: context.texts.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.l10n.radarHint,
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: onToggleSound,
          icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
          label: Text(
            soundOn ? context.l10n.radarSoundOn : context.l10n.radarSoundOff,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onFavoritePressed,
          icon: Icon(isFavorite ? Icons.star : Icons.star_border),
          label: Text(
            isFavorite
                ? context.l10n.radarFavoriteRemove
                : context.l10n.radarFavoriteAdd,
          ),
        ),
      ],
    );
  }
}
