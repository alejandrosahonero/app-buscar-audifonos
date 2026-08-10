import 'package:app_template/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demo state for the template's example feature.
///
/// Replace it with your real feature state; what matters is the shape:
/// an immutable state class + a `Notifier` that persists every mutation, with
/// no ad or review logic inside (that orchestration belongs to the screen).
@immutable
class HomeState {
  const HomeState({required this.completedActions, required this.credits});

  final int completedActions;
  final int credits;

  HomeState copyWith({int? completedActions, int? credits}) => HomeState(
    completedActions: completedActions ?? this.completedActions,
    credits: credits ?? this.credits,
  );
}

final NotifierProvider<HomeController, HomeState> homeControllerProvider =
    NotifierProvider<HomeController, HomeState>(HomeController.new);

class HomeController extends Notifier<HomeState> {
  static const String _actionsKey = 'home_completed_actions';
  static const String _creditsKey = 'home_credits';

  @override
  HomeState build() {
    final store = ref.watch(keyValueStoreProvider);
    return HomeState(
      completedActions: store.getInt(_actionsKey),
      credits: store.getInt(_creditsKey),
    );
  }

  Future<void> completeAction() async {
    final int value = state.completedActions + 1;
    state = state.copyWith(completedActions: value);
    await ref.read(keyValueStoreProvider).setInt(_actionsKey, value);
  }

  /// Persists the reward as soon as it is granted. A reward that only lives in
  /// memory is a support ticket waiting to happen: the user watched the video.
  Future<void> addCredits(int amount) async {
    final int value = state.credits + amount;
    state = state.copyWith(credits: value);
    await ref.read(keyValueStoreProvider).setInt(_creditsKey, value);
  }
}
