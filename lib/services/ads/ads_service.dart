import 'dart:async';
import 'dart:math' as math;

import 'package:app_template/core/config/ad_config.dart';
import 'package:app_template/core/config/app_config.dart';
import 'package:app_template/core/utils/app_logger.dart';
import 'package:app_template/services/ads/consent_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Result of an attempt to show a full screen ad.
enum AdShowResult {
  /// The ad was displayed.
  shown,

  /// Ads are off for this user (premium, no consent, SDK not ready).
  disabled,

  /// Pacing rules said "not yet" (action counter or minimum interval).
  skipped,

  /// Ads are on but no creative was cached. Never block the user for this.
  notReady,
}

/// Alias kept because the format-specific name reads better at call sites in
/// some features. `AdsService` is the canonical name used by the project guide.
typedef AdService = AdsService;

/// Single entry point for every AdMob format.
///
/// Design rules baked in here (they exist to protect the AdMob account and the
/// Play listing, so do not bypass them from feature code):
///
/// * Premium users never see an ad — the check lives here, not in the screens.
/// * Consent (UMP) is gathered before the first ad request.
/// * Interstitials need BOTH N value-actions and a minimum elapsed time.
/// * Full screen ads expire after ~1 h and are re-requested.
/// * Failed loads retry with exponential backoff, capped.
/// * A missing ad never blocks a user flow: callers get [AdShowResult.notReady]
///   and continue.
class AdsService {
  AdsService({required ConsentService consentService, required this.isPremium})
    : _consent = consentService;

  final ConsentService _consent;

  /// Injected instead of read from a provider so this class stays testable and
  /// free of Riverpod imports.
  final bool Function() isPremium;

  bool _initialized = false;

  InterstitialAd? _interstitial;
  DateTime? _interstitialLoadedAt;
  int _interstitialRetries = 0;
  bool _interstitialLoading = false;
  Timer? _interstitialRetryTimer;

  RewardedAd? _rewarded;
  DateTime? _rewardedLoadedAt;
  int _rewardedRetries = 0;
  bool _rewardedLoading = false;
  Timer? _rewardedRetryTimer;

  int _actionsSinceInterstitial = 0;
  DateTime? _lastInterstitialAt;

  /// True when an ad may be requested at all.
  bool get adsEnabled => _initialized && _consent.canRequestAds && !isPremium();

  /// Banners are additionally gated on having a configured unit id, so an
  /// unfinished production configuration degrades to "no banner" instead of a
  /// runtime error.
  bool get canShowBanner => adsEnabled && AdConfig.bannerAdUnitId.isNotEmpty;

  String get bannerAdUnitId => AdConfig.bannerAdUnitId;

  AdRequest buildRequest() => const AdRequest();

  /// Initializes the SDK, gathers consent and warms the ad cache.
  ///
  /// Call it AFTER the first frame (see `bootstrap.dart`): none of this may
  /// delay the first paint.
  Future<void> initialize() async {
    if (_initialized) return;

    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        tagForChildDirectedTreatment: AdConfig.isChildDirected
            ? TagForChildDirectedTreatment.yes
            : TagForChildDirectedTreatment.unspecified,
        maxAdContentRating: AdConfig.isChildDirected
            ? MaxAdContentRating.g
            : MaxAdContentRating.t,
        testDeviceIds: AdConfig.testDeviceIds,
      ),
    );

    // Consent must be resolved before the first ad request.
    await _consent.gatherConsent();
    await MobileAds.instance.initialize();

    _initialized = true;

    if (!adsEnabled) return;
    preload();
  }

  /// Warms up the full screen formats. Cheap to call repeatedly: each loader
  /// no-ops while a request is in flight or a valid creative is cached.
  void preload() {
    if (!adsEnabled) return;
    _loadInterstitial();
    _loadRewarded();
  }

  // --- Interstitial -------------------------------------------------------

  /// Registers a completed "value action" (task finished, level cleared,
  /// returned to home) and shows an interstitial when the pacing rules allow
  /// it.
  ///
  /// Never call this on a screen transition the user did not trigger, and never
  /// right after opening the app.
  Future<AdShowResult> registerActionAndMaybeShowInterstitial() async {
    if (!adsEnabled) return AdShowResult.disabled;

    _actionsSinceInterstitial++;
    if (_actionsSinceInterstitial < AppConfig.interstitialEveryNActions) {
      return AdShowResult.skipped;
    }

    final DateTime? last = _lastInterstitialAt;
    if (last != null &&
        DateTime.now().difference(last) <
            AppConfig.minIntervalBetweenInterstitials) {
      return AdShowResult.skipped;
    }

    return showInterstitial();
  }

  /// Shows a cached interstitial, ignoring the action counter but still
  /// honouring premium/consent gating.
  Future<AdShowResult> showInterstitial() async {
    if (!adsEnabled) return AdShowResult.disabled;

    if (_isExpired(_interstitialLoadedAt)) {
      _disposeInterstitial();
      _loadInterstitial();
    }

    final InterstitialAd? ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return AdShowResult.notReady;
    }

    // Detach before showing: the field must be null while the ad is on screen
    // so a second call cannot show the same instance twice.
    _interstitial = null;
    _interstitialLoadedAt = null;

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        AppLogger.error('Interstitial show failed: $error', name: 'ads');
        ad.dispose();
        _loadInterstitial();
      },
    );

    _actionsSinceInterstitial = 0;
    _lastInterstitialAt = DateTime.now();
    await ad.show();
    return AdShowResult.shown;
  }

  void _loadInterstitial() {
    if (!adsEnabled ||
        _interstitialLoading ||
        _interstitial != null ||
        AdConfig.interstitialAdUnitId.isEmpty) {
      return;
    }

    _interstitialLoading = true;
    unawaited(
      InterstitialAd.load(
        adUnitId: AdConfig.interstitialAdUnitId,
        request: buildRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            _interstitialLoading = false;
            _interstitialRetries = 0;
            _interstitial = ad;
            _interstitialLoadedAt = DateTime.now();
          },
          onAdFailedToLoad: (LoadAdError error) {
            _interstitialLoading = false;
            AppLogger.debug('Interstitial load failed: $error', name: 'ads');
            _scheduleRetry(
              retries: _interstitialRetries,
              onRetry: () {
                _interstitialRetries++;
                _loadInterstitial();
              },
              assignTimer: (Timer? timer) => _interstitialRetryTimer = timer,
            );
          },
        ),
      ),
    );
  }

  void _disposeInterstitial() {
    _interstitial?.dispose();
    _interstitial = null;
    _interstitialLoadedAt = null;
  }

  // --- Rewarded -----------------------------------------------------------

  /// Shows a rewarded video.
  ///
  /// [onRewardEarned] fires **only** from the SDK's `onUserEarnedReward`
  /// callback — never assume the reward from a dismissal. The caller is
  /// responsible for showing the "watch a video to get X" dialog beforehand and
  /// for persisting the reward.
  Future<AdShowResult> showRewarded({
    required void Function(RewardItem reward) onRewardEarned,
  }) async {
    if (!adsEnabled) return AdShowResult.disabled;

    if (_isExpired(_rewardedLoadedAt)) {
      _disposeRewarded();
      _loadRewarded();
    }

    final RewardedAd? ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return AdShowResult.notReady;
    }

    _rewarded = null;
    _rewardedLoadedAt = null;

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        // Preload the next one immediately: rewarded inventory is the main
        // revenue driver and a cold cache means a lost impression.
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        AppLogger.error('Rewarded show failed: $error', name: 'ads');
        ad.dispose();
        _loadRewarded();
      },
    );

    await ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) =>
          onRewardEarned(reward),
    );
    return AdShowResult.shown;
  }

  /// Whether a rewarded video is cached right now. Use it to disable or relabel
  /// the entry point instead of letting the user tap into a dead end.
  bool get isRewardedReady =>
      _rewarded != null && !_isExpired(_rewardedLoadedAt);

  void _loadRewarded() {
    if (!adsEnabled ||
        _rewardedLoading ||
        _rewarded != null ||
        AdConfig.rewardedAdUnitId.isEmpty) {
      return;
    }

    _rewardedLoading = true;
    unawaited(
      RewardedAd.load(
        adUnitId: AdConfig.rewardedAdUnitId,
        request: buildRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _rewardedLoading = false;
            _rewardedRetries = 0;
            _rewarded = ad;
            _rewardedLoadedAt = DateTime.now();
          },
          onAdFailedToLoad: (LoadAdError error) {
            _rewardedLoading = false;
            AppLogger.debug('Rewarded load failed: $error', name: 'ads');
            _scheduleRetry(
              retries: _rewardedRetries,
              onRetry: () {
                _rewardedRetries++;
                _loadRewarded();
              },
              assignTimer: (Timer? timer) => _rewardedRetryTimer = timer,
            );
          },
        ),
      ),
    );
  }

  void _disposeRewarded() {
    _rewarded?.dispose();
    _rewarded = null;
    _rewardedLoadedAt = null;
  }

  // --- Shared helpers -----------------------------------------------------

  bool _isExpired(DateTime? loadedAt) {
    if (loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) > AppConfig.fullScreenAdTtl;
  }

  /// Exponential backoff: 4 s, 8 s, 16 s, 32 s… then stop. Hammering a failing
  /// ad unit wastes battery and gets the app throttled by the SDK.
  void _scheduleRetry({
    required int retries,
    required void Function() onRetry,
    required void Function(Timer?) assignTimer,
  }) {
    if (retries >= AppConfig.adMaxRetries) return;

    final Duration delay =
        AppConfig.adRetryBaseDelay * math.pow(2, retries).toDouble();
    assignTimer(Timer(delay, onRetry));
  }

  /// Drops every cached ad. Called when the user becomes premium and from the
  /// provider's `onDispose`.
  void disposeAds() {
    _interstitialRetryTimer?.cancel();
    _rewardedRetryTimer?.cancel();
    _interstitialRetryTimer = null;
    _rewardedRetryTimer = null;
    _disposeInterstitial();
    _disposeRewarded();
  }
}
