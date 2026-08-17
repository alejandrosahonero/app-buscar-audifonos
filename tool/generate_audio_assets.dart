/// Generates the WAV asset used by the Geiger-style locator sound.
///
/// It is tiny, fully synthetic and deterministic, so it is generated from this
/// script instead of being committed as an opaque binary nobody can audit or
/// tweak. Regenerate it with:
///
///     dart run tool/generate_audio_assets.dart
///
/// Format is 16-bit mono PCM at 44.1 kHz: the smallest thing every Android
/// device decodes natively, and the only one SoundPool (audioplayers'
/// low-latency mode) handles without a codec round trip.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int _sampleRate = 44100;

void main() {
  // Short, bright click. Anything longer than ~80 ms starts to overlap itself
  // at the fastest Geiger rate and turns into a buzz.
  _writeWav(
    'assets/audio/beep.wav',
    _renderClick(frequency: 1800, duration: const Duration(milliseconds: 70)),
  );
}

/// A decaying sine burst: fast linear attack (no start click) followed by an
/// exponential decay (percussive, easy to count by ear).
Float64List _renderClick({
  required double frequency,
  required Duration duration,
}) {
  const int microsecondsPerSecond = 1000000;
  final int sampleCount =
      _sampleRate * duration.inMicroseconds ~/ microsecondsPerSecond;
  const int attackSamples = _sampleRate ~/ 250; // 4 ms
  final Float64List samples = Float64List(sampleCount);

  for (int i = 0; i < sampleCount; i++) {
    final double t = i / _sampleRate;
    final double attack = i < attackSamples ? i / attackSamples : 1;
    final double decay = math.exp(-t * 38);
    samples[i] = math.sin(2 * math.pi * frequency * t) * attack * decay * 0.85;
  }

  return samples;
}

void _writeWav(String path, Float64List samples) {
  const int bitsPerSample = 16;
  const int channels = 1;
  final int dataSize = samples.length * bitsPerSample ~/ 8;

  final BytesBuilder builder = BytesBuilder();
  builder.add(_ascii('RIFF'));
  builder.add(_uint32(36 + dataSize));
  builder.add(_ascii('WAVE'));
  builder.add(_ascii('fmt '));
  builder.add(_uint32(16)); // PCM header length.
  builder.add(_uint16(1)); // Format 1 = uncompressed PCM.
  builder.add(_uint16(channels));
  builder.add(_uint32(_sampleRate));
  builder.add(_uint32(_sampleRate * channels * bitsPerSample ~/ 8));
  builder.add(_uint16(channels * bitsPerSample ~/ 8));
  builder.add(_uint16(bitsPerSample));
  builder.add(_ascii('data'));
  builder.add(_uint32(dataSize));

  final Uint8List pcm = Uint8List(dataSize);
  final ByteData view = ByteData.view(pcm.buffer);
  for (int i = 0; i < samples.length; i++) {
    final int value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    view.setInt16(i * 2, value, Endian.little);
  }
  builder.add(pcm);

  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(builder.takeBytes());
  stdout.writeln('wrote $path (${file.lengthSync()} bytes)');
}

List<int> _ascii(String value) => value.codeUnits;

List<int> _uint16(int value) =>
    (Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little));

List<int> _uint32(int value) =>
    (Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little));
