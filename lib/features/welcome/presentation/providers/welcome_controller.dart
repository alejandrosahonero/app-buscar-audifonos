import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the first-run welcome has been completed.
///
/// Synchronous, read from preferences already loaded in `bootstrap`, so the
/// router can decide the very first route without a frame of the wrong screen.
final NotifierProvider<WelcomeController, bool> welcomeDoneProvider =
    NotifierProvider<WelcomeController, bool>(WelcomeController.new);

class WelcomeController extends Notifier<bool> {
  static const String storageKey = 'welcome_done';

  @override
  bool build() => ref.watch(keyValueStoreProvider).getBool(storageKey);

  Future<void> complete() async {
    state = true;
    await ref.read(keyValueStoreProvider).setBool(storageKey, value: true);
  }
}
