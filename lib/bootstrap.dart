import 'dart:async';

import 'package:app_template/app.dart';
import 'package:app_template/core/utils/app_logger.dart';
import 'package:app_template/services/ads/ads_providers.dart';
import 'package:app_template/services/billing/premium_controller.dart';
import 'package:app_template/services/review/review_providers.dart';
import 'package:app_template/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application entry point logic.
///
/// Startup budget: first frame under 2 s on a mid-range device. Only two things
/// are allowed to run before `runApp`:
///
/// * `WidgetsFlutterBinding.ensureInitialized()`
/// * loading `SharedPreferences` (a few milliseconds, and it lets the theme and
///   the counters render correctly on the very first frame).
///
/// Everything else — AdMob, UMP consent, billing — starts **after** the first
/// frame in [_initializeAfterFirstFrame].
Future<void> bootstrap() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.error(
          'Flutter error',
          error: details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        AppLogger.error('Platform error', error: error, stackTrace: stack);
        return true;
      };

      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      final ProviderContainer container = ProviderContainer(
        // `Override` is not exported by flutter_riverpod; the literal's type is
        // inferred from the element.
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );

      unawaited(container.read(reviewServiceProvider).registerAppStart());

      runApp(
        UncontrolledProviderScope(container: container, child: const App()),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeAfterFirstFrame(container));
      });
    },
    (Object error, StackTrace stackTrace) {
      AppLogger.error(
        'Uncaught zone error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

/// Deferred initialization. Any failure here degrades a feature; none of it may
/// crash the app or block the UI.
Future<void> _initializeAfterFirstFrame(ProviderContainer container) async {
  try {
    // Entitlement first: `AdsService` must know whether the user is premium
    // before it requests the first ad.
    await container.read(premiumControllerProvider.future);
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Billing initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    await container.read(adsServiceProvider).initialize();
    container.read(adsInitializedProvider.notifier).markInitialized();
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Ads initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
