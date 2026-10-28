// The About page's Round carousel: turns right to left on its own, and after
// a spin it settles back to that speed instead of stopping.

import 'package:Bloomee/screens/widgets/round_carousel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a flick settles back to the idle speed and keeps turning', () {
    final s = SettleSpin(0, 6, RoundCarousel.cruise);
    expect(s.dx(0), 6);
    expect(s.dx(5), closeTo(RoundCarousel.cruise, 0.01));
    expect(s.dx(30), closeTo(RoundCarousel.cruise, 1e-9));
    expect(s.isDone(1000), isFalse);
    // Position keeps moving at the idle speed long after the flick.
    expect(s.x(31) - s.x(30), closeTo(RoundCarousel.cruise, 1e-6));
  });

  test('idle turning is right to left', () {
    // The front card sits at x = sin(angle) * radius: a falling angle moves
    // it left.
    expect(RoundCarousel.cruise, lessThan(0));
  });
}
