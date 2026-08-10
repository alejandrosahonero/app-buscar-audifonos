import 'package:flutter/foundation.dart';

/// Build environments. Selected with `--dart-define=APP_ENV=prod` and matched
/// by the Android product flavors (`dev` / `prod`).
enum AppEnvironment { dev, prod }

/// Immutable, compile-time application configuration.
///
/// Everything that changes between environments lives here so no feature code
/// has to branch on `kReleaseMode` by itself.
abstract final class AppConfig {
  static const String _rawEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// Current environment. Defaults to [AppEnvironment.dev] so a plain
  /// `flutter run` never touches production resources.
  static final AppEnvironment environment = switch (_rawEnv) {
    'prod' => AppEnvironment.prod,
    _ => AppEnvironment.dev,
  };

  static bool get isProd => environment == AppEnvironment.prod;

  /// Real ads (production ad unit ids) are only ever requested from a release
  /// build of the `prod` flavor. Requesting production ads from a debug build
  /// is the fastest way to get an AdMob account banned for invalid traffic.
  static bool get useProductionAds => isProd && kReleaseMode;

  /// Shown in Settings. Keep in sync with `version:` in pubspec.yaml.
  static const String versionName = '1.0.0';

  // --- Ad pacing ----------------------------------------------------------

  /// Number of "value actions" between two interstitials.
  ///
  /// Combined with [minIntervalBetweenInterstitials]: BOTH conditions must be
  /// satisfied. The guide caps interstitials at ~1 every 3–4 minutes.
  static const int interstitialEveryNActions = 3;

  /// Hard floor between two interstitials, regardless of the action counter.
  static const Duration minIntervalBetweenInterstitials = Duration(minutes: 3);

  /// Full screen ads are cached server-side for about an hour. Anything older
  /// is discarded and re-requested so we never show a stale creative.
  static const Duration fullScreenAdTtl = Duration(minutes: 55);

  /// Base delay for the exponential backoff used when an ad fails to load.
  static const Duration adRetryBaseDelay = Duration(seconds: 4);

  /// Maximum number of consecutive retries before giving up until the next
  /// explicit request.
  static const int adMaxRetries = 4;

  // --- In-app review pacing ----------------------------------------------

  /// Successful "value moments" required before the review prompt is allowed.
  static const int reviewMinSuccessfulActions = 5;

  /// Minimum lifetime of the install before asking for a review.
  static const Duration reviewMinAppAge = Duration(days: 3);

  /// Minimum distance between two review prompts. Google throttles the dialog
  /// anyway; asking less often keeps the quota for the good moments.
  static const Duration reviewMinInterval = Duration(days: 120);

  // --- Rewards ------------------------------------------------------------

  /// Credits granted by one rewarded video in the demo feature.
  static const int rewardedCredits = 10;
}
