import 'dart:async';

import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash and error reporting, on Firebase Crashlytics.
///
/// Everything the app logs as an error already funnels through [AppLogger], so
/// this class is wired in there as a sink rather than being called from feature
/// code. Two consequences worth knowing:
///
/// * A feature never imports Firebase. Swapping Crashlytics for something else
///   touches this file and `bootstrap.dart`, nothing more.
/// * The report carries the log message as its `reason`, which is what makes a
///   Crashlytics issue readable without opening the stack trace.
///
/// **Nothing about the user is attached.** `setUserIdentifier` is deliberately
/// never called and no custom keys are set, so a report cannot be tied back to
/// a person by anything this app puts in it.
class CrashReporter {
  bool _enabled = false;

  /// Whether reports are actually being sent. False on a build with no Firebase
  /// configuration, and false in debug.
  bool get isEnabled => _enabled;

  /// Starts Firebase and turns collection on.
  ///
  /// Runs after the first frame (see `bootstrap.dart`), like every other
  /// service: `Firebase.initializeApp` touches the platform and the startup
  /// budget does not have room for it. That is not a hole in the coverage —
  /// the native Crashlytics SDK installs itself from a ContentProvider when the
  /// process starts, so a native or JVM crash during startup is still caught;
  /// only Dart errors raised before this point go unreported.
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } on Object catch (error) {
      // Almost always the expected case rather than a failure: there is no
      // `android/app/google-services.json` in this build, so the Gradle plugin
      // was never applied and there is no configuration to read. The app runs
      // fine without crash reporting — it just does not report.
      AppLogger.debug(
        'Crash reporting is not configured for this build: $error',
        name: 'crash',
      );
      return;
    }

    // Never collect from a debug build: it floods the dashboard with crashes
    // the developer caused on purpose and poisons the crash-free rate that
    // Play's Android Vitals reads.
    _enabled = !kDebugMode;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      _enabled,
    );
  }

  /// Sends one error. Called by [AppLogger], not by feature code.
  ///
  /// `fatal` is the difference between "the app died" and "something failed and
  /// the app handled it". Only the three global handlers in `bootstrap.dart`
  /// report fatal errors; a caught exception is non-fatal, because counting
  /// handled degradations as crashes would wreck the crash-free rate that
  /// decides whether Play keeps showing the app.
  void report({
    required String message,
    required bool fatal,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_enabled) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error ?? message,
        stackTrace,
        reason: message,
        fatal: fatal,
      ),
    );
  }
}
