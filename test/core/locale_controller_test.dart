import 'package:buscar_audifonos/core/l10n/locale_controller.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with nothing stored the app follows the phone', () async {
    final ProviderContainer container = await _container(<String, Object>{});

    expect(container.read(localeProvider), isNull);
  });

  test('a stored language is restored', () async {
    final ProviderContainer container = await _container(<String, Object>{
      'app_locale': 'en',
    });

    expect(container.read(localeProvider), const Locale('en'));
  });

  test('choosing the system language again clears the choice', () async {
    final ProviderContainer container = await _container(<String, Object>{
      'app_locale': 'en',
    });

    await container.read(localeProvider.notifier).setLocale(null);

    expect(container.read(localeProvider), isNull);
  });

  test('a language the app does not ship falls back to the phone', () async {
    // A dropped translation, or a hand-edited preference. Pinning the UI to a
    // locale with no strings behind it would leave the app unreadable.
    final ProviderContainer container = await _container(<String, Object>{
      'app_locale': 'kl',
    });

    expect(container.read(localeProvider), isNull);
  });

  test('the choice survives a restart', () async {
    final ProviderContainer first = await _container(<String, Object>{});
    await first.read(localeProvider.notifier).setLocale(const Locale('es'));

    // A fresh container over the same preferences is what a relaunch looks
    // like: the value has to come back synchronously, before the first frame.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    expect(second.read(localeProvider), const Locale('es'));
  });
}
