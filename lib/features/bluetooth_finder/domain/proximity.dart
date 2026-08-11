import 'dart:math' as math;

/// How close the tracked device feels, derived from its signal strength.
enum ProximityBand {
  /// Keep walking: the signal is barely there.
  far,

  /// Same room. Sweep slowly.
  near,

  /// Within arm's reach — this is the "found it" moment.
  veryNear,
}

/// Conversion from raw RSSI (dBm) to the 0..1 closeness value the radar paints
/// and the Geiger sound is paced with.
///
/// RSSI is *not* a distance: it is attenuated by bodies, walls, pockets and the
/// transmitter's own power. The app therefore never claims a distance in
/// metres — it shows a relative "closeness" the user can hill-climb by walking
/// around, which is what actually finds a lost earbud.
abstract final class Proximity {
  /// Weakest reading still treated as a signal. Below this the device is out of
  /// practical range for a hand-held search.
  static const int minRssi = -100;

  /// Strongest realistic reading. BLE radios rarely report above this even when
  /// the device is touching the phone, so clamping here keeps the top of the
  /// scale reachable instead of theoretical.
  static const int maxRssi = -30;

  /// Weight of the newest sample in the moving average applied to every device.
  ///
  /// Raw RSSI swings 10-15 dBm between consecutive advertisements of a
  /// stationary device. Without smoothing the radar jitters so much it is
  /// unusable; with too much smoothing it lags behind the user's movement.
  static const double smoothingFactor = 0.35;

  /// Closeness in 0..1. Accepts a double because it is fed the smoothed
  /// average, not the raw integer sample.
  static double fromRssi(double rssi) =>
      ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);

  /// The same value as a 0-100 integer, for display.
  static int percent(double rssi) => (fromRssi(rssi) * 100).round();

  static ProximityBand bandFor(double closeness) {
    if (closeness >= 0.72) return ProximityBand.veryNear;
    if (closeness >= 0.40) return ProximityBand.near;
    return ProximityBand.far;
  }

  /// Exponential moving average over the RSSI samples of one device.
  static double smooth(double previous, int sample) =>
      previous + (sample - previous) * smoothingFactor;

  /// Delay between two Geiger clicks for a given closeness.
  ///
  /// Interpolated on a curve rather than linearly: the ear resolves changes in
  /// a fast click train much better than in a slow one, so the useful
  /// resolution belongs at the near end of the scale.
  static Duration clickInterval(double closeness) {
    const int slowestMs = 1100;
    const int fastestMs = 90;
    final double eased = math.pow(closeness.clamp(0.0, 1.0), 0.7).toDouble();
    return Duration(
      milliseconds: (slowestMs + (fastestMs - slowestMs) * eased).round(),
    );
  }
}
