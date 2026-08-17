import 'package:flutter/foundation.dart';

/// Immutable, compile-time application configuration.
///
/// There is no environment concept and no `--dart-define`: a single build
/// configuration, with the release/debug distinction Flutter already gives us.
/// The one decision that ever needed environments is [useProductionAds], and
/// it is safer keyed off the build mode.
abstract final class AppConfig {
  /// Real ads (production ad unit ids) are only ever requested from a release
  /// build. Requesting production ads from a debug build is the fastest way to
  /// get an AdMob account banned for invalid traffic.
  ///
  /// Keyed off [kReleaseMode] alone, so the protection cannot be defeated by
  /// forgetting a command line argument.
  static bool get useProductionAds => kReleaseMode;

  /// Shown in Settings. Keep in sync with `version:` in pubspec.yaml.
  static const String versionName = '1.0.0';

  /// Public URL of the privacy policy.
  ///
  /// Google Play **requires** one for any app that uses AdMob, because the ads
  /// SDK collects the advertising id. The same URL has to be entered in the
  /// Play Console listing — this constant only drives the in-app link.
  ///
  /// Empty until the document is published, and an empty value **hides** the
  /// Settings row rather than opening a broken link: the same "an unconfigured
  /// value disables the feature" rule the ad unit ids follow.
  static const String privacyPolicyUrl = '';

  static bool get hasPrivacyPolicy => privacyPolicyUrl.isNotEmpty;

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
