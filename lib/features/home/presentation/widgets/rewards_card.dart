import 'package:app_template/core/config/app_config.dart';
import 'package:app_template/core/extensions/build_context_x.dart';
import 'package:app_template/core/theme/app_spacing.dart';
import 'package:app_template/core/widgets/section_card.dart';
import 'package:app_template/features/home/presentation/providers/home_controller.dart';
import 'package:app_template/services/ads/ads_providers.dart';
import 'package:app_template/services/ads/ads_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded video entry point.
///
/// The correct flow, in order:
/// 1. Explain the reward in a dialog and let the user opt in.
/// 2. Show the ad.
/// 3. Grant the reward **only** from `onUserEarnedReward`, and persist it.
/// 4. If no ad is cached, degrade gracefully — the feature must never become
///    unusable because there is no ad inventory.
class RewardsCard extends ConsumerWidget {
  const RewardsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int credits = ref.watch(
      homeControllerProvider.select((HomeState state) => state.credits),
    );

    return SectionCard(
      title: context.l10n.rewardsTitle,
      icon: Icons.card_giftcard,
      children: <Widget>[
        Text(
          context.l10n.rewardsBalance(credits),
          style: context.texts.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => _watchAd(context, ref),
          icon: const Icon(Icons.play_circle_outline),
          label: Text(context.l10n.rewardsWatchAd(AppConfig.rewardedCredits)),
        ),
      ],
    );
  }

  Future<void> _watchAd(BuildContext context, WidgetRef ref) async {
    final bool accepted = await _confirm(context);
    if (!accepted || !context.mounted) return;

    final AdShowResult result = await ref
        .read(adsServiceProvider)
        .showRewarded(
          onRewardEarned: (RewardItem reward) => _grantReward(ref, reward),
        );

    if (!context.mounted) return;

    switch (result) {
      case AdShowResult.shown:
        break;
      case AdShowResult.notReady:
      case AdShowResult.disabled:
      case AdShowResult.skipped:
        // No inventory (or premium/no consent): do not punish the user.
        context.showSnack(context.l10n.rewardsAdUnavailable);
    }
  }

  /// Grants and persists the reward. Fire-and-forget on purpose: the SDK
  /// callback is synchronous and must not be blocked.
  void _grantReward(WidgetRef ref, RewardItem reward) {
    final int amount = reward.amount.toInt() > 0
        ? reward.amount.toInt()
        : AppConfig.rewardedCredits;
    ref.read(homeControllerProvider.notifier).addCredits(amount).ignore();
  }

  Future<bool> _confirm(BuildContext context) async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.rewardsDialogTitle(AppConfig.rewardedCredits),
        ),
        content: Text(dialogContext.l10n.rewardsDialogBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.commonContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }
}
