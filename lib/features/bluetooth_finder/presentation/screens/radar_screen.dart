import 'dart:async';

import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/core/widgets/base_screen.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/data/geiger_sounder.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/continuous_mode_controller.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/radar_view.dart';
import 'package:buscar_audifonos/services/ads/ads_providers.dart';
import 'package:buscar_audifonos/services/ads/ads_service.dart';
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

  /// Name captured on entry, so the header does not go blank the moment the
  /// device stops advertising.
  String? _lastKnownName;
  bool _soundOn = false;
  bool _reviewRequested = false;

  @override
  void initState() {
    super.initState();

    // `ref.listen` (below) only fires on *changes*, so seed from whatever the
    // scan already knows about this device.
    final DiscoveredDevice? current = ref.read(
      deviceByIdProvider(widget.deviceId),
    );
    if (current != null && current.hasName) _lastKnownName = current.name;

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
      _rememberName(next);
      _maybeRequestReview(next);
    });

    final DiscoveredDevice? device = ref.watch(
      deviceByIdProvider(widget.deviceId),
    );
    final bool unlocked = ref.watch(continuousModeUnlockedProvider);

    return BaseScreen(
      title: _lastKnownName ?? context.l10n.finderUnnamedDevice,
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
              Text(
                widget.deviceId,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
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
                continuousUnlocked: unlocked,
                onToggleSound: _toggleSound,
                onContinuousPressed: unlocked
                    ? _enableContinuous
                    : _unlockContinuous,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps the last resolved name so the header does not go blank the moment
  /// the device stops advertising.
  void _rememberName(DiscoveredDevice device) {
    if (!device.hasName || device.name == _lastKnownName) return;
    setState(() => _lastKnownName = device.name);
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    _sounder.muted = !_soundOn;
  }

  void _enableContinuous() {
    setState(() => _soundOn = true);
    _sounder
      ..continuous = true
      ..muted = false;
    context.showSnack(context.l10n.radarContinuousEnabled);
  }

  /// Rewarded flow, in the order the project guide mandates:
  /// explain → show → grant only from `onUserEarnedReward` → degrade politely
  /// when there is no inventory.
  Future<void> _unlockContinuous() async {
    final bool accepted = await _confirmRewarded();
    if (!accepted || !mounted) return;

    final AdShowResult result = await ref
        .read(adsServiceProvider)
        .showRewarded(onRewardEarned: _grantContinuous);

    if (!mounted) return;

    switch (result) {
      case AdShowResult.shown:
        break;
      // No inventory, or the SDK is not ready yet (premium users never get
      // here — `continuousModeUnlockedProvider` already grants them the mode).
      // Either way: inform, never dead-end.
      case AdShowResult.disabled:
      case AdShowResult.notReady:
      case AdShowResult.skipped:
        context.showSnack(context.l10n.rewardsAdUnavailable);
    }
  }

  void _grantContinuous(RewardItem reward) {
    ref.read(rewardedContinuousModeProvider.notifier).grant();
    if (mounted) _enableContinuous();
  }

  Future<bool> _confirmRewarded() async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.radarContinuousDialogTitle),
        content: Text(dialogContext.l10n.radarContinuousDialogBody),
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
    required this.continuousUnlocked,
    required this.onToggleSound,
    required this.onContinuousPressed,
  });

  final bool soundOn;
  final bool continuousUnlocked;
  final VoidCallback onToggleSound;
  final VoidCallback onContinuousPressed;

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
          onPressed: onContinuousPressed,
          icon: Icon(
            continuousUnlocked ? Icons.graphic_eq : Icons.play_circle_outline,
          ),
          label: Text(
            continuousUnlocked
                ? context.l10n.radarContinuousMode
                : context.l10n.radarContinuousLocked,
          ),
        ),
      ],
    );
  }
}
