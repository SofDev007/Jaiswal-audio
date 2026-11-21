import 'package:Bloomee/services/player/listening_time.dart';
import 'package:Bloomee/services/your_corner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plays count into the total and into their month', () {
    final s = ListeningStats(DateTime(2026, 11, 13), 0, {});
    s.countNow(DateTime(2026, 11, 20), 'a', 'Kesariya', 'Arijit Singh', 60000, 1);
    s.countNow(DateTime(2026, 12, 2), 'b', 'Perfect', 'Ed Sheeran', 30000, 1);
    expect(s.totalMs, 90000);
    expect(s.months['2026-11']!.totalMs, 60000);
    expect(s.months['2026-12']!.topArtists(5).single.name, 'Ed Sheeran');

    final back = ListeningStats.fromJson(s.toJson());
    expect(back.months['2026-11']!.songs['a']!.plays, 1);
    expect(back.months.keys, ['2026-11', '2026-12']);
  });

  test('a record saved before months existed becomes its start month', () {
    final old = ListeningStats(DateTime(2026, 11, 13), 120000, {
      'arijit singh': (name: 'Arijit Singh', ms: 120000),
    }).toJson();
    final s = ListeningStats.fromJson(old);
    expect(s.months['2026-11']!.totalMs, 120000);
  });

  test('another phone adds into the same months', () {
    final a = ListeningStats(DateTime(2026, 11, 1), 0, {})
      ..countNow(DateTime(2026, 11, 5), 'x', 'X', 'AP Dhillon', 1000, 0);
    final b = ListeningStats(DateTime(2026, 11, 1), 0, {})
      ..countNow(DateTime(2026, 11, 6), 'x', 'X', 'AP Dhillon', 2000, 1);
    a.add(b);
    expect(a.months['2026-11']!.totalMs, 3000);
    expect(a.months['2026-11']!.songs['x']!.plays, 1);
  });

  test('only the last 24 months are kept', () {
    final s = ListeningStats(DateTime(2024, 1, 1), 0, {});
    for (var m = 0; m < 30; m++) {
      s.countNow(DateTime(2024, 1 + m, 10), 'a', 'A', 'B', 1000, 0);
    }
    expect(s.months.length, 24);
    expect(s.months.containsKey('2024-01'), isFalse);
    expect(s.totalMs, 30000, reason: 'totals keep everything');
  });

  test('first 3 days of a month show last month', () {
    final s = ListeningStats(DateTime(2026, 11, 13), 0, {})
      ..countNow(DateTime(2026, 11, 20), 'a', 'A', 'B', 60000, 1);
    expect(cornerMonth(s, DateTime(2026, 12, 2)).label, 'November');
    expect(cornerMonth(s, DateTime(2026, 12, 4)).label, 'December');
    expect(cornerMonth(s, DateTime(2026, 12, 4)).stats.totalMs, 0);
    expect(cornerMonth(s, DateTime(2026, 11, 21)).label, 'November');
  });

  test('silly comparisons stay readable', () {
    expect(sillyComparison(1, 0), isNull);
    // 390 min: Titanic = 2, never "0.09 Mahabharats".
    final all = {for (var d = 0; d < 20; d++) sillyComparison(390, d)!};
    expect(all, contains("That's 2 Titanic movies, back to back."));
    expect(all.any((t) => t.contains('Mahabharat')), isFalse);
    expect(sillyComparison(5, 4), 'That’s 2.5 packets of 2-minute Maggi.');
    expect(minutesText(65 * 60000), '1 h 05 min');
    expect(minutesText(42 * 60000), '42 min');
  });
}
