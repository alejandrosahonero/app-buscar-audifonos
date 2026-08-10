import 'package:app_template/core/extensions/build_context_x.dart';
import 'package:app_template/core/theme/app_spacing.dart';
import 'package:app_template/core/widgets/section_card.dart';
import 'package:app_template/features/home/presentation/providers/home_controller.dart';
import 'package:app_template/services/ads/ads_providers.dart';
import 'package:app_template/services/review/review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demo of the "value action" flow.
///
/// This is the canonical order for a successful action, and the reason the
/// interstitial and the review prompt live here rather than in the controller:
///
/// 1. Do the real work and persist it.
/// 2. Ask the ad service whether an interstitial is due (it applies the pacing
///    rules; a "no" is normal and must not be worked around).
/// 3. Only then consider the review prompt — never after an error.
class TaskCard extends ConsumerWidget {
  const TaskCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int completed = ref.watch(
      homeControllerProvider.select(
        (HomeState state) => state.completedActions,
      ),
    );

    return SectionCard(
      title: context.l10n.homeTitle,
      icon: Icons.task_alt,
      children: <Widget>[
        Text(context.l10n.homeSubtitle, style: context.texts.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.homeCounterLabel(completed),
          style: context.texts.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => _completeTask(context, ref),
          icon: const Icon(Icons.check),
          label: Text(context.l10n.homeCompleteTask),
        ),
      ],
    );
  }

  Future<void> _completeTask(BuildContext context, WidgetRef ref) async {
    await ref.read(homeControllerProvider.notifier).completeAction();

    if (!context.mounted) return;
    context.showSnack(context.l10n.homeTaskDone);

    // The service decides: N actions AND a minimum elapsed time.
    await ref.read(adsServiceProvider).registerActionAndMaybeShowInterstitial();

    // Success moment → the only acceptable place for the review prompt.
    await ref.read(reviewServiceProvider).requestReviewAfterSuccess();
  }
}
