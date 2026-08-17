import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Where an [AppLogger.error] is forwarded once crash reporting is running.
///
/// A callback rather than a direct import so this file — reached from pure
/// logic with no platform behind it — never depends on Firebase, and so tests
/// exercise the real logger without a crash reporting SDK in the way.
typedef CrashSink =
    void Function({
      required String message,
      required bool fatal,
      Object? error,
      StackTrace? stackTrace,
    });

/// Minimal logging facade.
///
/// `print` is banned by the analyzer: it survives into release builds and slows
/// down the platform channel. Everything goes through `dart:developer`, which
/// is stripped in release mode by [kDebugMode] guards.
///
/// Every error in the app funnels through [error], which is what makes this the
/// single place crash reporting has to be attached to — see [attachCrashSink]
/// and `services/crash/crash_reporter.dart`.
abstract final class AppLogger {
  static CrashSink? _crashSink;

  /// Connects the crash reporter. Called once from `bootstrap.dart`, after the
  /// reporter has started; before that, errors are only logged locally. Pass
  /// `null` to disconnect it again, which is how a test cleans up after itself.
  static void attachCrashSink(CrashSink? sink) => _crashSink = sink;

  static void debug(String message, {String name = 'app'}) {
    if (!kDebugMode) return;
    developer.log(message, name: name);
  }

  /// Logs an error and reports it.
  ///
  /// [fatal] means "the app is going down", and only the global handlers in
  /// `bootstrap.dart` set it. Everything else here is an exception that was
  /// caught and handled, which must stay non-fatal: counting those as crashes
  /// would sink the crash-free rate Play judges the app by.
  static void error(
    String message, {
    String name = 'app',
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
  }) {
    developer.log(
      message,
      name: name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _crashSink?.call(
      message: message,
      fatal: fatal,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
