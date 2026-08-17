import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// One report as the crash sink received it.
typedef _Report = ({
  String message,
  bool fatal,
  Object? error,
  StackTrace? stackTrace,
});

void main() {
  late List<_Report> reports;

  setUp(() {
    reports = <_Report>[];
    AppLogger.attachCrashSink(
      ({
        required String message,
        required bool fatal,
        Object? error,
        StackTrace? stackTrace,
      }) => reports.add((
        message: message,
        fatal: fatal,
        error: error,
        stackTrace: stackTrace,
      )),
    );
  });

  tearDown(() => AppLogger.attachCrashSink(null));

  test('an error is forwarded to the crash reporter with its context', () {
    final StackTrace trace = StackTrace.current;
    AppLogger.error('Billing failed', error: 'boom', stackTrace: trace);

    expect(reports, hasLength(1));
    expect(reports.single.message, 'Billing failed');
    expect(reports.single.error, 'boom');
    expect(reports.single.stackTrace, trace);
  });

  test('a caught error is non fatal by default', () {
    AppLogger.error('Ads initialization failed', error: 'boom');

    // The crash-free rate Play judges the app by must only count real crashes,
    // so anything a `try/catch` handled has to stay out of it.
    expect(reports.single.fatal, isFalse);
  });

  test('only an explicitly fatal error is reported as a crash', () {
    AppLogger.error('Uncaught zone error', error: 'boom', fatal: true);

    expect(reports.single.fatal, isTrue);
  });

  test('a debug message is never reported', () {
    AppLogger.debug('just noise');

    expect(reports, isEmpty);
  });

  test('nothing is reported once the sink is detached', () {
    AppLogger.attachCrashSink(null);
    AppLogger.error('happens before Crashlytics is up', error: 'boom');

    expect(reports, isEmpty);
  });
}
