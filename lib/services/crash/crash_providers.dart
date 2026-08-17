import 'package:buscar_audifonos/services/crash/crash_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kept alive on purpose, like `adsServiceProvider`: it owns the "is collection
/// on" flag for the whole process, and disposing it would silently stop the
/// reporting the moment no screen happened to be watching.
final Provider<CrashReporter> crashReporterProvider = Provider<CrashReporter>(
  (Ref ref) => CrashReporter(),
);
