// The visualizer turns Android's waveform bytes into drawable values.

import 'dart:math';
import 'dart:typed_data';

import 'package:Bloomee/screens/widgets/live_visualizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('silence stays flat; a loud sine fills the line', () {
    final f = VisualizerFrame();
    f.addWave(Uint8List(512)..fillRange(0, 512, 128));
    expect(f.wave.every((v) => v == 0), isTrue);

    final sine = Uint8List.fromList(
        [for (var i = 0; i < 512; i++) (128 + 120 * sin(i / 4)).round()]);
    for (var i = 0; i < 5; i++) {
      f.addWave(sine);
    }
    expect(f.wave.map((v) => v.abs()).reduce(max), greaterThan(0.5));
  });
}
