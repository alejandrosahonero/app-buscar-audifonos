import 'dart:async';

import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/discovered_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// State of the Bluetooth radio, normalized so no UI code has to import the
/// plugin's own enum.
enum BluetoothAvailability {
  /// Radio on and usable.
  ready,

  /// Present but switched off. Recoverable through [BluetoothScanService.requestEnable].
  off,

  /// The OS refused access (permissions revoked, or a work-profile policy).
  unauthorized,

  /// No Bluetooth Low Energy hardware. The finder cannot work here at all.
  unsupported,

  /// The first adapter event has not arrived yet.
  unknown,
}

/// Bluetooth Low Energy scanning, wrapped so the rest of the app only ever sees
/// [DiscoveredDevice] and [BluetoothAvailability].
///
/// Pure logic, no `BuildContext`: permissions are requested by the screen
/// through `PermissionFlow` *before* [start] is called, exactly like the
/// template's `PermissionService` / `PermissionFlow` split. That keeps this
/// class testable and callable from non-UI code.
///
/// ## Scope: BLE only
///
/// `flutter_blue_plus` scans Bluetooth **Low Energy** advertisements. Android
/// exposes no API to read the RSSI of a classic (BR/EDR) discovery through it,
/// so classic-only headsets will not appear here. In practice modern earbuds
/// and headphones advertise over BLE even while their audio link is classic,
/// which is what makes the radar work for them. [bondedDeviceIds] is provided
/// so the UI can at least mark already-paired devices.
class BluetoothScanService {
  BluetoothScanService() {
    // `scanResults` is a re-emitting broadcast stream, but `map` runs once per
    // listener. Subscribing exactly once here guarantees the moving average is
    // fed a single time per advertisement batch.
    _subscription = FlutterBluePlus.scanResults.listen(
      _onResults,
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'Scan stream failed',
        name: 'bluetooth',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  final StreamController<List<DiscoveredDevice>> _devices =
      StreamController<List<DiscoveredDevice>>.broadcast();

  late final StreamSubscription<List<ScanResult>> _subscription;

  Map<String, DiscoveredDevice> _known = <String, DiscoveredDevice>{};
  List<DiscoveredDevice> _latest = const <DiscoveredDevice>[];
  bool _logConfigured = false;

  /// A device is dropped from the list after this long without advertising.
  /// Long enough to survive a few missed packets, short enough that a device
  /// carried out of the room disappears while the user is still looking at it.
  static const Duration _gonePatience = Duration(seconds: 12);

  /// Devices seen in the current scan, newest reading first.
  ///
  /// Replays the last emission to every new listener, so navigating to the
  /// radar screen and back does not blank the list until the next packet.
  Stream<List<DiscoveredDevice>> get devices async* {
    yield _latest;
    yield* _devices.stream;
  }

  List<DiscoveredDevice> get latestDevices => _latest;

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  bool get isScanningNow => FlutterBluePlus.isScanningNow;

  Stream<BluetoothAvailability> get availability =>
      FlutterBluePlus.adapterState.map(_toAvailability);

  /// Ids of devices already paired with the phone. Used only to badge the list:
  /// a paired device is very likely the one the user is hunting for.
  Future<Set<String>> bondedDeviceIds() async {
    try {
      final List<BluetoothDevice> bonded = await FlutterBluePlus.bondedDevices;
      return bonded
          .map((BluetoothDevice device) => device.remoteId.str)
          .toSet();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Reading bonded devices failed',
        name: 'bluetooth',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String>{};
    }
  }

  /// Starts a continuous scan. Safe to call when a scan is already running.
  ///
  /// Throws nothing: failures are logged and reported through [availability],
  /// because a finder app must degrade to "nothing found" rather than crash.
  Future<void> start() async {
    if (FlutterBluePlus.isScanningNow) return;

    if (!_logConfigured) {
      _logConfigured = true;
      // The plugin logs every advertisement at debug level, which is thousands
      // of lines a minute on a busy channel.
      await FlutterBluePlus.setLogLevel(
        kDebugMode ? LogLevel.warning : LogLevel.none,
      );
    }

    _known = <String, DiscoveredDevice>{};
    _emit(const <DiscoveredDevice>[]);

    try {
      await FlutterBluePlus.startScan(
        // The whole point of this app: keep receiving duplicate advertisements
        // so the RSSI keeps updating. Without it the plugin reports each device
        // once and the radar freezes on its first reading.
        continuousUpdates: true,
        // Process every packet. This is the knob to trade radar responsiveness
        // for battery if profiling ever demands it.
        continuousDivisor: 1,
        removeIfGone: _gonePatience,
        androidScanMode: AndroidScanMode.lowLatency,
        // We already asked for ACCESS_FINE_LOCATION through PermissionService,
        // bundled with the Bluetooth group in a single dialog sequence. Letting
        // the plugin ask again would show a second prompt out of context.
        androidUsesFineLocation: false,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'startScan failed',
        name: 'bluetooth',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> stop() async {
    try {
      await FlutterBluePlus.stopScan();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'stopScan failed',
        name: 'bluetooth',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Asks Android to turn the radio on (system dialog). No-op elsewhere.
  Future<void> requestEnable() async {
    try {
      await FlutterBluePlus.turnOn();
    } on Object catch (error) {
      // The user declining the system dialog throws. Not an error.
      AppLogger.debug('turnOn refused: $error', name: 'bluetooth');
    }
  }

  void _onResults(List<ScanResult> results) {
    final Map<String, DiscoveredDevice> next = <String, DiscoveredDevice>{};

    for (final ScanResult result in results) {
      final String id = result.device.remoteId.str;
      // `platformName` is the cached GATT name (survives across packets);
      // `advName` is what this particular advertisement carried. Either can be
      // empty, so prefer whichever we actually have.
      final String name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : result.advertisementData.advName;

      final DiscoveredDevice? previous = _known[id];
      next[id] = previous == null
          ? DiscoveredDevice.firstSeen(
              id: id,
              name: name,
              rssi: result.rssi,
              lastSeen: result.timeStamp,
            )
          : previous.merge(
              name: name,
              rssi: result.rssi,
              lastSeen: result.timeStamp,
            );
    }

    _known = next;
    _emit(next.values.toList(growable: false));
  }

  void _emit(List<DiscoveredDevice> devices) {
    _latest = devices;
    if (!_devices.isClosed) _devices.add(devices);
  }

  BluetoothAvailability _toAvailability(BluetoothAdapterState state) =>
      switch (state) {
        BluetoothAdapterState.on => BluetoothAvailability.ready,
        BluetoothAdapterState.off ||
        BluetoothAdapterState.turningOff => BluetoothAvailability.off,
        BluetoothAdapterState.turningOn => BluetoothAvailability.unknown,
        BluetoothAdapterState.unauthorized =>
          BluetoothAvailability.unauthorized,
        BluetoothAdapterState.unavailable => BluetoothAvailability.unsupported,
        BluetoothAdapterState.unknown => BluetoothAvailability.unknown,
      };

  /// Releases the platform subscription. Wired to the provider's `onDispose`.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _devices.close();
  }
}
