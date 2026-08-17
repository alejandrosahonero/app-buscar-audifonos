import 'package:buscar_audifonos/core/config/app_config.dart';

/// AdMob identifiers.
///
/// Two complete sets are kept side by side: the official Google test ids and
/// the production ones. [AppConfig.useProductionAds] decides which set is
/// exposed, so a debug build can never request a production ad unit.
///
/// **The App ID is the exception, and it matters.** It lives in
/// `android/app/src/main/AndroidManifest.xml`, which cannot switch on the build
/// mode, so the production App ID is now baked into every build including
/// debug. That is the configuration Google documents and it is safe *because*
/// the unit ids above still switch: a debug build identifies the app with the
/// real App ID but only ever requests test creatives, which earn nothing and
/// count for nothing.
///
/// What is **not** safe is running a *release* build on your own phone and
/// touching the ads: those are real requests against real units, and AdMob
/// bans accounts for that. Put your device in [testDeviceIds] first.
///
/// [prodAppId] is duplicated here only so the value in the manifest has a
/// findable counterpart in Dart; nothing reads it.
abstract final class AdConfig {
  // --- Official Google test unit ids -------------------------------------
  // https://developers.google.com/admob/android/test-ads
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const String _testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  // --- Production unit ids -------------------------------------------------
  // Only ever requested from a release build ([AppConfig.useProductionAds]).
  // An empty id would disable that format rather than crash, which is what
  // kept the app working before these existed.
  static const String prodAppId = 'ca-app-pub-4073049276319773~8873347767';
  static const String _prodBanner = 'ca-app-pub-4073049276319773/7194947351';
  static const String _prodInterstitial =
      'ca-app-pub-4073049276319773/5680157884';
  static const String _prodRewarded = 'ca-app-pub-4073049276319773/6055612731';

  static String get bannerAdUnitId =>
      AppConfig.useProductionAds ? _prodBanner : _testBanner;

  static String get interstitialAdUnitId =>
      AppConfig.useProductionAds ? _prodInterstitial : _testInterstitial;

  static String get rewardedAdUnitId =>
      AppConfig.useProductionAds ? _prodRewarded : _testRewarded;

  /// Whether the app targets children. Drives `tagForChildDirectedTreatment`
  /// and `maxAdContentRating`; must match the Play Console target audience
  /// declaration.
  static const bool isChildDirected = false;

  /// Device ids that should always receive test ads, even in a release build.
  /// The id is printed in logcat the first time the SDK requests an ad.
  static const List<String> testDeviceIds = <String>[];
}
