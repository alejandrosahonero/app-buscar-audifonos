import 'package:app_template/core/extensions/build_context_x.dart';
import 'package:app_template/core/routing/app_routes.dart';
import 'package:app_template/core/theme/app_spacing.dart';
import 'package:app_template/core/widgets/base_screen.dart';
import 'package:app_template/features/home/presentation/widgets/permissions_card.dart';
import 'package:app_template/features/home/presentation/widgets/rewards_card.dart';
import 'package:app_template/features/home/presentation/widgets/task_card.dart';
import 'package:app_template/services/billing/premium_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Example screen wiring every integration together.
///
/// Uses [BaseScreen], so the banner is handled for free. `ListView` (not
/// `Column` + `SingleChildScrollView`) because the content grows as features
/// are added and only the visible cards should be built.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isPremium = ref.watch(isPremiumProvider);

    return BaseScreen(
      title: context.l10n.appTitle,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.goNamed(AppRoutes.settingsName),
          icon: const Icon(Icons.settings_outlined),
          tooltip: context.l10n.settingsTitle,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        children: <Widget>[
          if (isPremium) const _PremiumBadge(),
          const TaskCard(),
          const SizedBox(height: AppSpacing.md),
          const RewardsCard(),
          const SizedBox(height: AppSpacing.md),
          const PermissionsCard(),
          if (!isPremium) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const _RemoveAdsEntryPoint(),
          ],
        ],
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.verified, color: context.semanticColors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.premiumActive,
              style: context.texts.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Discreet paywall entry point.
///
/// Shown after the content, never as a blocking screen on first launch: the
/// paywall must follow a value moment.
class _RemoveAdsEntryPoint extends StatelessWidget {
  const _RemoveAdsEntryPoint();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.goNamed(AppRoutes.paywallName),
      icon: const Icon(Icons.block),
      label: Text(context.l10n.settingsRemoveAds),
    );
  }
}
