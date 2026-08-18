import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/scan_filter.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/providers/scanner_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two list filters, as toggle chips on a single scrolling row.
///
/// Both default to on. Turning them off is the escape hatch for the rare case
/// where the target really is an anonymous or very faint device.
///
/// One row rather than a `Wrap`: the bar sits directly above the list and a
/// second line of chips pushes the devices down on exactly the phones that have
/// least room for them. The row scrolls instead, and a chip the user just
/// tapped is scrolled fully into view — a half-cut chip is unreadable, and the
/// half that gets cut is the label that says what the filter does.
class ScanFilterBar extends ConsumerStatefulWidget {
  const ScanFilterBar({required this.hiddenCount, super.key});

  /// How many devices the filters are currently keeping out of the list. Shown
  /// so an empty list never looks like a broken scan.
  final int hiddenCount;

  @override
  ConsumerState<ScanFilterBar> createState() => _ScanFilterBarState();
}

class _ScanFilterBarState extends ConsumerState<ScanFilterBar> {
  final GlobalKey _identifiedKey = GlobalKey();
  final GlobalKey _strongSignalKey = GlobalKey();

  /// Brings a chip fully into view after it was tapped.
  ///
  /// Deferred to the end of the frame: the chip changes width when it gains or
  /// loses its checkmark, and scrolling to where it *was* would leave it cut
  /// off by exactly that difference.
  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = key.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        // Centred: with a chip at either end of the row, aligning to the edge
        // would leave it flush against the screen border.
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ScanFilter filter = ref.watch(scanFilterProvider);
    final ScanFilterController controller = ref.read(
      scanFilterProvider.notifier,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          FilterChip(
            key: _identifiedKey,
            selected: filter.hideUnidentified,
            onSelected: (bool value) {
              controller.setHideUnidentified(value: value).ignore();
              _reveal(_identifiedKey);
            },
            avatar: const Icon(Icons.label_outline, size: 18),
            label: Text(context.l10n.finderFilterIdentifiedOnly),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            key: _strongSignalKey,
            selected: filter.hideWeakSignal,
            onSelected: (bool value) {
              controller.setHideWeakSignal(value: value).ignore();
              _reveal(_strongSignalKey);
            },
            avatar: const Icon(Icons.signal_cellular_alt, size: 18),
            label: Text(context.l10n.finderFilterStrongSignal),
          ),
          if (widget.hiddenCount > 0) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Text(
              context.l10n.finderHiddenCount(widget.hiddenCount),
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
