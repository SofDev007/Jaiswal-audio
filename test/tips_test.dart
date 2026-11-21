import 'package:Bloomee/services/tips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day1 = DateTime(2026, 11, 22, 10);
  final day2 = DateTime(2026, 11, 23, 10);

  test('off until the first-run flow turns tips on', () {
    expect(TipBook().pick(['A1'], day1), isNull);
    expect(TipBook(enabled: true).pick(['A1'], day1), 'A1');
  });

  test('each tip once; the more important one first', () {
    final b = TipBook(enabled: true);
    expect(b.pick(['A1', 'T14'], day1), 'T14', reason: 'photo tip comes first');
    b.markShown('T14', day1);
    expect(b.pick(['A1', 'T14'], day1), 'A1');
  });

  test('at most 3 a day, more the next day', () {
    final b = TipBook(enabled: true);
    for (final id in ['T14', 'A1', 'T16']) {
      b.markShown(id, day1);
    }
    expect(b.pick(['A2'], day1), isNull);
    expect(b.pick(['A2'], day2), 'A2');
  });

  test('sleep timer tip waits for the second time the player opens', () {
    final b = TipBook(enabled: true);
    b.counts['player'] = 1;
    expect(b.pick(['T2'], day1), isNull);
    b.counts['player'] = 2;
    expect(b.pick(['T2'], day1), 'T2');
  });

  test('survives a save and load', () {
    final b = TipBook(enabled: true)..markShown('A1', day1);
    b.counts['player'] = 3;
    final back = TipBook.fromJson(b.toJson());
    expect(back.enabled, isTrue);
    expect(back.shown, {'A1'});
    expect(back.today, 1);
    expect(back.counts['player'], 3);
  });
}
