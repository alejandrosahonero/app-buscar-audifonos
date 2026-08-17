import 'package:buscar_audifonos/l10n/generated/app_localizations.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persisted language preference.
///
/// `null` means "follow the phone", which is the default and what most users
/// should stay on. An explicit choice exists because this app is used in
/// households where the phone language is not the language the owner reads
/// best, and because a Spanish speaker with an English phone should not have to
/// change the whole system to read the app.
///
/// Synchronous by design, exactly like `ThemeModeController`: the value comes
/// from `SharedPreferences`, already loaded in `bootstrap`, so the first frame
/// paints in the right language instead of flashing the wrong one.
final NotifierProvider<LocaleController, Locale?> localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);

class LocaleController extends Notifier<Locale?> {
  static const String _storageKey = 'app_locale';

  /// Sentinel for "follow the system". Stored as a value of its own rather than
  /// by removing the key, so "never chose" and "chose to follow the phone" stay
  /// distinguishable if that ever matters.
  static const String _systemValue = 'system';

  @override
  Locale? build() {
    final String? stored = ref
        .watch(keyValueStoreProvider)
        .getString(_storageKey);

    if (stored == null || stored == _systemValue) return null;

    // A stored language the app no longer ships (a translation was dropped, or
    // the value was hand-edited) falls back to the system rather than pinning
    // the UI to a locale with no strings behind it.
    return AppLocalizations.supportedLocales.cast<Locale?>().firstWhere(
      (Locale? locale) => locale!.languageCode == stored,
      orElse: () => null,
    );
  }

  /// Pass `null` to follow the phone again.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await ref
        .read(keyValueStoreProvider)
        .setString(_storageKey, locale?.languageCode ?? _systemValue);
  }
}
