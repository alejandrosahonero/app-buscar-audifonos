import 'dart:convert';

import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/favorite_device.dart';
import 'package:buscar_audifonos/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// The user's pinned devices, newest last, persisted across launches.
///
/// Kept alive (no `autoDispose`): the scanner screen and the radar screen both
/// read it, and re-parsing the stored JSON every time the user opens a radar
/// would be work for nothing.
final NotifierProvider<FavoriteDevicesController, List<FavoriteDevice>>
favoriteDevicesProvider =
    NotifierProvider<FavoriteDevicesController, List<FavoriteDevice>>(
      FavoriteDevicesController.new,
    );

/// Just the identifiers, for the two places that only need a membership test.
///
/// A separate provider so a radar screen watching "is this one pinned?" does
/// not rebuild every time an unrelated favourite is renamed.
final Provider<Set<String>> favoriteDeviceIdsProvider = Provider<Set<String>>((
  Ref ref,
) {
  return ref
      .watch(favoriteDevicesProvider)
      .map((FavoriteDevice favorite) => favorite.id)
      .toSet();
});

final ProviderFamily<bool, String> isFavoriteProvider =
    Provider.family<bool, String>(
      (Ref ref, String id) => ref.watch(favoriteDeviceIdsProvider).contains(id),
      isAutoDispose: true,
    );

/// Reads and writes the favourites list.
///
/// Stored as one JSON array under a single key rather than as a list of ids:
/// the description has to survive alongside the id, because an offline
/// favourite has no advertisement left to resolve a name from.
class FavoriteDevicesController extends Notifier<List<FavoriteDevice>> {
  static const String _key = 'finder_favorite_devices';

  @override
  List<FavoriteDevice> build() {
    final String? raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null || raw.isEmpty) return const <FavoriteDevice>[];

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <FavoriteDevice>[];
      return List<FavoriteDevice>.unmodifiable(
        decoded.map(FavoriteDevice.fromJson).nonNulls,
      );
    } on FormatException catch (error) {
      // Corrupted storage must not take the whole screen down with it: the user
      // loses their pins, not the app.
      AppLogger.error(
        'Stored favourites could not be read',
        name: 'finder',
        error: error,
      );
      return const <FavoriteDevice>[];
    }
  }

  /// Pins [device], or refreshes the stored description if it was already
  /// pinned — a device that was anonymous when it was first saved may have
  /// advertised its real name since.
  Future<void> add(DiscoveredDevice device) {
    final FavoriteDevice favorite = FavoriteDevice.fromDiscovered(device);
    return _write(<FavoriteDevice>[
      for (final FavoriteDevice existing in state)
        if (existing.id != favorite.id) existing,
      favorite,
    ]);
  }

  Future<void> remove(String id) {
    if (!state.any((FavoriteDevice favorite) => favorite.id == id)) {
      return Future<void>.value();
    }
    return _write(<FavoriteDevice>[
      for (final FavoriteDevice favorite in state)
        if (favorite.id != id) favorite,
    ]);
  }

  /// State first, storage second: pinning is a reward the user just paid a
  /// video for, so the row appears on the next frame instead of waiting for a
  /// disk write.
  Future<void> _write(List<FavoriteDevice> favorites) {
    state = List<FavoriteDevice>.unmodifiable(favorites);
    return ref
        .read(keyValueStoreProvider)
        .setString(
          _key,
          jsonEncode(
            favorites
                .map((FavoriteDevice favorite) => favorite.toJson())
                .toList(),
          ),
        );
  }
}
