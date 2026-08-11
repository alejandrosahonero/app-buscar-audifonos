import 'package:buscar_audifonos/services/billing/premium_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the radar's continuous-tone mode is available right now.
///
/// True when the user is premium (they paid, they get everything) or when they
/// watched a rewarded video during this session.
final Provider<bool> continuousModeUnlockedProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(isPremiumProvider) || ref.watch(rewardedContinuousModeProvider),
);

/// The rewarded half of the unlock.
///
/// Deliberately **not** persisted: the dialog promises "for this session", and
/// a reward that silently outlives what was promised turns the rewarded video
/// into a one-time purchase — which kills the format's revenue and misleads the
/// user in the opposite direction. Kept alive (no `autoDispose`) so leaving the
/// radar screen does not revoke it.
final NotifierProvider<RewardedContinuousMode, bool>
rewardedContinuousModeProvider = NotifierProvider<RewardedContinuousMode, bool>(
  RewardedContinuousMode.new,
);

class RewardedContinuousMode extends Notifier<bool> {
  @override
  bool build() => false;

  /// Call this **only** from the ad SDK's `onUserEarnedReward` callback.
  void grant() => state = true;
}
