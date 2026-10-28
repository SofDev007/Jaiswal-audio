// The visualizer turns Android's waveform/FFT bytes into drawable values.

import 'dart:math';
import 'dart:typed_data';

import 'package:Bloomee/screens/widgets/live_visualizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('silence stays flat; a loud sine fills the line and levels', () {
    final f = VisualizerFrame();
    f.addWave(Uint8List(512)..fillRange(0, 512, 128));
    expect(f.wave.every((v) => v == 0), isTrue);
    expect(f.levels.every((v) => v == 0), isTrue);

    final sine = Uint8List.fromList(
        [for (var i = 0; i < 512; i++) (128 + 120 * sin(i / 4)).round()]);
    for (var i = 0; i < 5; i++) {
      f.addWave(sine);
    }
    expect(f.wave.map((v) => v.abs()).reduce(max), greaterThan(0.5));
    expect(f.levels.every((v) => v > 0.5), isTrue);
  });

  test('a strong low bin lights the bass bars, not the treble', () {
    final f = VisualizerFrame();
    final fft = Int8List(512);
    fft[2] = 120; // bin 1, real part
    f.addFft(Uint8List.sublistView(fft));
    expect(f.bands.first, greaterThan(0.8));
    expect(f.bands.last, 0);
  });
}
