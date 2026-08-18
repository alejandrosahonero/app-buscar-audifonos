import 'package:buscar_audifonos/core/extensions/build_context_x.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_identity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/device_taxonomy.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/presentation/widgets/signal_strength_icon.dart';
import 'package:flutter/material.dart';

/// How a [DeviceIdentity] turns into words and pictures.
///
/// The domain resolves *what* a device is; everything here decides how to say
/// it. Single source of truth, so the list and the radar can never disagree
/// about what a device is called.

/// The icon that stands in for a whole category. One per category, so two
/// devices look alike in the list only when they really are alike.
IconData deviceCategoryIcon(DeviceCategory category) => switch (category) {
  DeviceCategory.earbuds => Icons.earbuds,
  DeviceCategory.headphones => Icons.headphones,
  DeviceCategory.speaker => Icons.speaker,
  DeviceCategory.hearingAid => Icons.hearing,
  DeviceCategory.watch => Icons.watch,
  DeviceCategory.fitnessBand => Icons.directions_run,
  DeviceCategory.phone => Icons.smartphone,
  DeviceCategory.computer => Icons.laptop,
  DeviceCategory.tablet => Icons.tablet,
  DeviceCategory.tv => Icons.tv,
  DeviceCategory.keyboard => Icons.keyboard,
  DeviceCategory.mouse => Icons.mouse,
  DeviceCategory.gamepad => Icons.sports_esports,
  DeviceCategory.tracker => Icons.local_offer,
  DeviceCategory.beacon => Icons.cell_tower,
  DeviceCategory.healthSensor => Icons.monitor_heart,
  DeviceCategory.carKit => Icons.directions_car,
  DeviceCategory.smartHome => Icons.home_outlined,
  DeviceCategory.unknown => Icons.bluetooth,
};

String deviceCategoryLabel(BuildContext context, DeviceCategory category) =>
    switch (category) {
      DeviceCategory.earbuds => context.l10n.finderCategoryEarbuds,
      DeviceCategory.headphones => context.l10n.finderCategoryHeadphones,
      DeviceCategory.speaker => context.l10n.finderCategorySpeaker,
      DeviceCategory.hearingAid => context.l10n.finderCategoryHearingAid,
      DeviceCategory.watch => context.l10n.finderCategoryWatch,
      DeviceCategory.fitnessBand => context.l10n.finderCategoryFitnessBand,
      DeviceCategory.phone => context.l10n.finderCategoryPhone,
      DeviceCategory.computer => context.l10n.finderCategoryComputer,
      DeviceCategory.tablet => context.l10n.finderCategoryTablet,
      DeviceCategory.tv => context.l10n.finderCategoryTv,
      DeviceCategory.keyboard => context.l10n.finderCategoryKeyboard,
      DeviceCategory.mouse => context.l10n.finderCategoryMouse,
      DeviceCategory.gamepad => context.l10n.finderCategoryGamepad,
      DeviceCategory.tracker => context.l10n.finderCategoryTracker,
      DeviceCategory.beacon => context.l10n.finderCategoryBeacon,
      DeviceCategory.healthSensor => context.l10n.finderCategoryHealthSensor,
      DeviceCategory.carKit => context.l10n.finderCategoryCarKit,
      DeviceCategory.smartHome => context.l10n.finderCategorySmartHome,
      DeviceCategory.unknown => context.l10n.finderUnnamedDevice,
    };

/// The best name we can put on a device, in descending order of confidence:
/// what it calls itself, the model we recognised, brand plus kind, kind alone.
///
/// Only the last rung is generic, and reaching it means the advertisement
/// genuinely said nothing — not that we did not look.
String deviceDisplayName(
  BuildContext context,
  DeviceIdentity identity, {
  String? customName,
}) {
  // Outranks everything the advertisement says: the user renamed this device
  // precisely because the advertised name did not tell them which one it was.
  if (customName != null && customName.isNotEmpty) return customName;

  if (identity.hasAdvertisedName) return identity.advertisedName;

  final String? model = identity.modelName;
  if (model != null) return model;

  final String category = deviceCategoryLabel(context, identity.category);
  final String? vendor = identity.vendor;
  if (vendor != null) {
    return context.l10n.finderDeviceNameWithVendor(category, vendor);
  }
  return category;
}

/// What kind of thing it is and who makes it, e.g. `Auriculares · Sony`.
///
/// `null` when the advertisement said neither.
String? deviceKindLine(BuildContext context, DeviceIdentity identity) {
  final List<String> parts = <String>[
    if (identity.category != DeviceCategory.unknown)
      deviceCategoryLabel(context, identity.category),
    ?identity.vendor,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// [deviceKindLine], suppressed when [deviceDisplayName] already had to fall
/// back to those same two facts — repeating "Auriculares de Sony / Auriculares
/// · Sony" one line below itself would be noise.
String? deviceSummaryLine(BuildContext context, DeviceIdentity identity) {
  if (!identity.hasAdvertisedName && identity.modelName == null) return null;
  return deviceKindLine(context, identity);
}

/// Round category badge, tinted by how close the device is.
///
/// Doubles as the proximity cue the old list used a bar icon for, so the icon
/// carries two facts in the space of one.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    required this.category,
    required this.band,
    this.color,
    this.size = 44,
    super.key,
  });

  final DeviceCategory category;
  final ProximityBand band;

  /// Overrides the proximity tint. Set it only when there is no proximity to
  /// show — a favourite that is out of range — so the badge does not claim a
  /// reading the app does not have.
  final Color? color;

  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = this.color ?? proximityColor(context, band);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(
        deviceCategoryIcon(category),
        color: color,
        size: size * 0.52,
      ),
    );
  }
}

/// The short, actionable facts about a device, as compact chips.
///
/// Capped at [maxChips] and ordered by usefulness — battery and "this is
/// already yours" beat a pairing-protocol badge. A tile crammed with six chips
/// stops being scannable, which is the only thing the list is for.
class DeviceMetaChips extends StatelessWidget {
  const DeviceMetaChips({
    required this.identity,
    this.isPaired = false,
    this.maxChips = 3,
    this.alignment = WrapAlignment.start,
    super.key,
  });

  final DeviceIdentity identity;
  final bool isPaired;
  final int maxChips;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = _chipsFor(context).take(maxChips).toList();
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: alignment,
      children: chips,
    );
  }

  List<Widget> _chipsFor(BuildContext context) {
    final Set<DeviceTrait> traits = identity.traits;
    final int? battery = identity.batteryPercent;

    return <Widget>[
      if (battery != null)
        DeviceMetaChip(
          icon: Icons.battery_full,
          label: context.l10n.finderMetaBattery(battery),
          highlighted: true,
        ),
      if (isPaired)
        DeviceMetaChip(
          icon: Icons.link,
          label: context.l10n.finderMetaPaired,
          highlighted: true,
        ),
      // The hearing-aid and beacon traits are skipped when they already named
      // the category — the line above the chips has just said it.
      if (traits.contains(DeviceTrait.hearingAid) &&
          identity.category != DeviceCategory.hearingAid)
        DeviceMetaChip(
          icon: Icons.hearing,
          label: context.l10n.finderCategoryHearingAid,
        ),
      if (traits.contains(DeviceTrait.findMy))
        DeviceMetaChip(
          icon: Icons.location_searching,
          label: context.l10n.finderTraitFindMy,
        ),
      if (traits.contains(DeviceTrait.leAudio))
        DeviceMetaChip(
          icon: Icons.graphic_eq,
          label: context.l10n.finderTraitLeAudio,
        ),
      if (traits.contains(DeviceTrait.fastPair))
        DeviceMetaChip(
          icon: Icons.bolt,
          label: context.l10n.finderTraitFastPair,
        ),
      if (traits.contains(DeviceTrait.swiftPair))
        DeviceMetaChip(
          icon: Icons.bolt,
          label: context.l10n.finderTraitSwiftPair,
        ),
      if (traits.contains(DeviceTrait.beacon) &&
          identity.category != DeviceCategory.beacon)
        DeviceMetaChip(
          icon: Icons.cell_tower,
          label: context.l10n.finderCategoryBeacon,
        ),
      // Weakest of the lot: true for most devices. It only earns a slot when
      // nothing more interesting filled the row.
      if (identity.connectable && !isPaired)
        DeviceMetaChip(
          icon: Icons.bluetooth,
          label: context.l10n.finderMetaPairable,
        ),
    ];
  }
}

/// One compact fact about a device.
///
/// Deliberately not a Material `Chip`: those carry a 32 dp minimum height and
/// their own margins, which is half a list row for two words of text.
class DeviceMetaChip extends StatelessWidget {
  const DeviceMetaChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Facts the user acts on (battery, "already yours") get the accent
  /// container; protocol badges stay quiet.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final Color background = highlighted
        ? context.colors.secondaryContainer
        : context.colors.surfaceContainerHighest;
    final Color foreground = highlighted
        ? context.colors.onSecondaryContainer
        : context.colors.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: context.texts.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
