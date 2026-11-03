// Recommendations Layer 2: the on-device model that learns this listener's
// weights from what they do with suggestions.

import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, double> _x({double novelty = 0, double language = 1}) => {
      'source': 0.5,
      'affinity': 0.3,
      'seedLink': 0.5,
      'duration': 0.8,
      'language': language,
      'mood': 0.5,
      'novelty': novelty,
      'timeMood': 0.5,
      'skipPenalty': 0,
      'foreign': language == 0 ? 1 : 0,
    };

void main() {
  test('a new listener gets exactly the Layer 1 weights', () {
    final m = TasteModel.fresh();
    for (final k in TasteModel.prior.keys) {
      expect(m.weight(k), TasteModel.prior[k]);
    }
  });

  test('skipping new songs and keeping known ones lowers "new to you"', () {
    final m = TasteModel.fresh();
    for (var i = 0; i < 40; i++) {
      m.learn(_x(novelty: 1), good: false);
      m.learn(_x(novelty: 0), good: true);
    }
    expect(m.weight('novelty'), lessThan(TasteModel.prior['novelty']!));
    expect(m.updates, 80);
    // A known song now looks better than a new one.
    expect(m.predict(_x(novelty: 0)), greaterThan(m.predict(_x(novelty: 1))));
  });

  test('one odd skip barely moves it; weights stay bounded', () {
    final m = TasteModel.fresh();
    m.learn(_x(), good: false);
    expect((m.weight('language') - TasteModel.prior['language']!).abs(),
        lessThan(0.03));
    for (var i = 0; i < 5000; i++) {
      m.learn(_x(), good: true, strength: 3);
    }
    for (final k in TasteModel.prior.keys) {
      expect(m.weight(k).abs(), lessThanOrEqualTo(1.0));
    }
  });

  test('moods played at this time of day score higher', () {
    final m = TasteModel.fresh();
    final saturdayNight = DateTime(2026, 11, 7, 23);
    final mondayMorning = DateTime(2026, 11, 9, 8);
    expect(m.timeMood({Mood.dance}, saturdayNight), 0.5); // nothing yet
    for (var i = 0; i < 12; i++) {
      m.notePlayMoods({Mood.dance}, saturdayNight);
      m.notePlayMoods({Mood.uplifting}, mondayMorning);
    }
    expect(m.timeMood({Mood.dance}, saturdayNight), greaterThan(0.9));
    expect(m.timeMood({Mood.romantic}, saturdayNight), 0.5);
    expect(m.timeMood({Mood.dance}, mondayMorning), 0.5);
  });
}
