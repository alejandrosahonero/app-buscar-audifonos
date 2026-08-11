import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:buscar_audifonos/core/utils/app_logger.dart';
import 'package:buscar_audifonos/features/bluetooth_finder/domain/proximity.dart';

/// Audible feedback for the radar, Geiger-counter style.
///
/// Two modes, both driven by the same 0..1 closeness value:
///
/// * **Clicks** (free): a short burst whose repetition rate accelerates as the
///   user gets closer. This is the mode that actually guides a search — the ear
///   detects a change in rate far better than a change in volume.
/// * **Continuous tone** (unlocked with a rewarded video): a looping tone whose
///   volume tracks closeness, for hunting in a noisy room where individual
///   clicks get lost.
///
/// No `BuildContext` and no Riverpod here: the screen owns the instance and
/// feeds it, so the timing logic can be reasoned about (and disposed) on its
/// own.
class GeigerSounder {
  GeigerSounder();

  /// Rescheduling on every RSSI sample would restart the timer constantly and
  /// the click train would stutter. Only a meaningful change re-arms it.
  static const Duration _intervalEpsilon = Duration(milliseconds: 40);

  /// Mix with other audio instead of taking audio focus.
  ///
  /// A player that owns the focus abandons it on every `stop()`, and the click
  /// train stops and restarts the stream up to eleven times a second: with the
  /// default `gain` focus that is a burst of focus requests that makes whatever
  /// else the phone is playing duck in and out.
  static final AudioContext _mixingContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  final AudioPlayer _clickPlayer = AudioPlayer(playerId: 'radar_click');
  final AudioPlayer _tonePlayer = AudioPlayer(playerId: 'radar_tone');

  /// Every call into `audioplayers` is asynchronous, so two transitions in
  /// flight at once get delivered in whatever order the platform answers —
  /// which is how the "pause the tone" of one transition lands *after* the
  /// "resume the tone" of the next and leaves the radar silent. All platform
  /// work is appended here and runs in the order it was requested.
  Future<void> _queue = Future<void>.value();

  final List<StreamSubscription<AudioEvent>> _errorSubscriptions =
      <StreamSubscription<AudioEvent>>[];

  Timer? _clickTimer;
  Duration _clickInterval = Duration.zero;
  double _closeness = 0;
  bool _muted = true;
  bool _continuous = false;
  bool _clickInFlight = false;
  bool _prepared = false;
  bool _disposed = false;

  bool get isMuted => _muted;

  /// Loads both sources into their backends. Call it once, off the first frame
  /// — the very first `play` on a cold player takes hundreds of milliseconds
  /// otherwise.
  Future<void> prepare() {
    if (_prepared || _disposed) return Future<void>.value();
    _prepared = true;
    _watchForPlatformErrors();
    return _enqueue(_load);
  }

  Future<void> _load() async {
    try {
      // The audio context goes first: applying it after the source is loaded
      // tears the prepared player down and reloads it.
      await _clickPlayer.setAudioContext(_mixingContext);
      await _clickPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _clickPlayer.setReleaseMode(ReleaseMode.stop);
      await _clickPlayer.setSource(AssetSource('audio/beep.wav'));

      await _tonePlayer.setAudioContext(_mixingContext);
      await _tonePlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _tonePlayer.setReleaseMode(ReleaseMode.loop);
      await _tonePlayer.setSource(AssetSource('audio/tone.wav'));
      await _tonePlayer.setVolume(0);
    } on Object catch (error, stackTrace) {
      // Loading is the one step worth a real error entry: if it fails the
      // radar is mute for the whole session.
      AppLogger.error(
        'Geiger sound could not be prepared',
        name: 'radar',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Feeds the current closeness (0..1). Cheap: call it on every reading.
  void updateCloseness(double closeness) {
    _closeness = closeness.clamp(0.0, 1.0);
    if (_continuous) {
      _applyToneVolume();
    } else {
      _rescheduleClicks();
    }
  }

  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    _restart();
  }

  /// Switches between the click train and the rewarded continuous tone.
  set continuous(bool value) {
    if (_continuous == value) return;
    _continuous = value;
    _restart();
  }

  void _restart() {
    _stopClicks();
    unawaited(_enqueue(_pauseTone));
    if (_muted || _disposed) return;

    if (_continuous) {
      unawaited(_enqueue(_startTone));
    } else {
      _clickInterval = Duration.zero;
      _rescheduleClicks();
    }
  }

  void _rescheduleClicks() {
    if (_muted || _continuous || _disposed) return;

    final Duration next = Proximity.clickInterval(_closeness);
    final Duration delta = next - _clickInterval;
    if (_clickTimer != null && delta.abs() < _intervalEpsilon) return;

    _clickInterval = next;
    _clickTimer?.cancel();
    // Periodic rather than self-rescheduling: the tick is what defines the
    // rhythm, and a dropped `play` must not stop the train.
    _clickTimer = Timer.periodic(next, (Timer _) => _playClick());
    _playClick();
  }

  void _playClick() {
    // At the fastest rate a tick can arrive while the previous one is still
    // talking to the platform. Skipping it keeps the stop/resume pair atomic;
    // one missing click in a train of eleven per second is inaudible.
    if (_muted || _continuous || _disposed || _clickInFlight) return;
    _clickInFlight = true;
    unawaited(_enqueue(_fireClick).whenComplete(() => _clickInFlight = false));
  }

  /// Restarts the one-shot burst.
  ///
  /// `stop()` before `resume()` is not a formality. The low-latency backend is
  /// SoundPool, which has no completion event, so the plugin still believes the
  /// player is playing after the first burst and silently ignores every later
  /// `resume()`. And `seek(Duration.zero)` — the usual way to rewind a one-shot
  /// — cannot be used either: SoundPool never emits `onSeekComplete`, so that
  /// future hangs until the plugin's 30 s seek timeout and the click never
  /// fires at all.
  Future<void> _fireClick() async {
    if (_muted || _continuous || _disposed) return;
    await _clickPlayer.stop();
    await _clickPlayer.resume();
  }

  void _stopClicks() {
    _clickTimer?.cancel();
    _clickTimer = null;
    _clickInterval = Duration.zero;
  }

  Future<void> _startTone() async {
    if (_muted || !_continuous || _disposed) return;
    // Volume before resume, so the first pass of the loop is already audible.
    await _tonePlayer.setVolume(_toneVolume);
    await _tonePlayer.resume();
  }

  Future<void> _pauseTone() async {
    await _tonePlayer.setVolume(0);
    await _tonePlayer.pause();
  }

  void _applyToneVolume() {
    if (_muted || !_continuous || _disposed) return;
    unawaited(_enqueue(() => _tonePlayer.setVolume(_toneVolume)));
  }

  /// Never fully silent while the mode is on: the user paid a video for a sound
  /// that is always there.
  double get _toneVolume => 0.25 + _closeness * 0.75;

  /// Appends [action] to the serialized queue.
  ///
  /// Playback errors are cosmetic — the radar still works silently — so a
  /// failed step is logged at debug level (a click runs up to eleven times a
  /// second; anything louder would be a flood) and the chain carries on.
  Future<void> _enqueue(Future<void> Function() action) {
    final Future<void> next = _queue.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } on Object catch (error) {
        AppLogger.debug('Radar sound step failed: $error', name: 'radar');
      }
    });
    _queue = next;
    return next;
  }

  /// The platform reports a broken source (missing asset, unsupported codec) as
  /// an error on the event stream, not as a failed call. Without a listener it
  /// is dropped and the radar just goes quiet with no way to tell why.
  void _watchForPlatformErrors() {
    for (final AudioPlayer player in <AudioPlayer>[_clickPlayer, _tonePlayer]) {
      _errorSubscriptions.add(
        player.eventStream.listen(
          null,
          onError: (Object error, StackTrace stackTrace) => AppLogger.error(
            'Radar audio player ${player.playerId} reported an error',
            name: 'radar',
            error: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopClicks();
    // Let the queue drain first: disposing a player while a call of its own is
    // still in flight throws on the platform side.
    await _queue;
    for (final StreamSubscription<AudioEvent> subscription
        in _errorSubscriptions) {
      await subscription.cancel();
    }
    _errorSubscriptions.clear();
    await _clickPlayer.dispose();
    await _tonePlayer.dispose();
  }
}
