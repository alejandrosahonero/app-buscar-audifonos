import 'package:app_template/services/ads/ads_service.dart';
import 'package:app_template/services/ads/consent_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Consent is not granted and the SDK was never initialized, which is exactly
/// the state the gating must handle: no ad request may leave the device.
void main() {
  test('ads stay disabled until the SDK is initialized', () {
    final AdsService service = AdsService(
      consentService: ConsentService(),
      isPremium: () => false,
    );

    expect(service.adsEnabled, isFalse);
    expect(service.canShowBanner, isFalse);
    expect(service.isRewardedReady, isFalse);
  });

  test('a premium user never triggers a full screen ad', () async {
    final AdsService service = AdsService(
      consentService: ConsentService(),
      isPremium: () => true,
    );

    expect(
      await service.registerActionAndMaybeShowInterstitial(),
      AdShowResult.disabled,
    );
    expect(
      await service.showRewarded(onRewardEarned: (_) {}),
      AdShowResult.disabled,
    );
  });
}
