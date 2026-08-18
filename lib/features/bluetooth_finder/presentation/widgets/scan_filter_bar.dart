import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/scan_filter.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two list filters, as toggle chips.
///
/// Both default to on. Turning them off is the escape hatch for the rare case
/// where the target really is an anonymous or very faint device.
class ScanFilterBar extends ConsumerWidget {
  const ScanFilterBar({required this.hiddenCount, super.key});

  /// How many devices the filters are currently keeping out of the list. Shown
  /// so an empty list never looks like a broken scan.
  final int hiddenCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ScanFilter filter = ref.watch(scanFilterProvider);
    final ScanFilterController controller = ref.read(
      scanFilterProvider.notifier,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      // `Wrap`, not `Row`: the chip labels grow with the locale and with the
      // system font scale, and a filter bar must never overflow.
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          FilterChip(
            selected: filter.hideUnidentified,
            onSelected: (bool value) =>
                controller.setHideUnidentified(value: value).ignore(),
            avatar: const Icon(Icons.label_outline, size: 18),
            label: Text(context.l10n.finderFilterIdentifiedOnly),
          ),
          FilterChip(
            selected: filter.hideWeakSignal,
            onSelected: (bool value) =>
                controller.setHideWeakSignal(value: value).ignore(),
            avatar: const Icon(Icons.signal_cellular_alt, size: 18),
            label: Text(context.l10n.finderFilterStrongSignal),
          ),
          if (hiddenCount > 0)
            Text(
              context.l10n.finderHiddenCount(hiddenCount),
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
