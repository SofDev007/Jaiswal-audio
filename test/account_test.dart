// The offline grace: signed-in phones work without internet for 10 days.

import 'package:Bloomee/services/account/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 13, 12);

  test('works offline for up to 10 days since the last check', () {
    expect(withinGrace(now.subtract(const Duration(days: 9)), now), isTrue);
    expect(withinGrace(now.subtract(const Duration(days: 10)), now), isFalse);
  });

  test('never checked, or a clock moved far back, needs the internet', () {
    expect(withinGrace(null, now), isFalse);
    expect(withinGrace(now.add(const Duration(days: 30)), now), isFalse);
  });

  test('a saved user survives a save and load', () {
    const u = JarxUser('1', 'a@b.com', 'Arnav', 'https://p');
    final back = JarxUser.fromJson(u.toJson());
    expect([back.id, back.email, back.name, back.photo],
        ['1', 'a@b.com', 'Arnav', 'https://p']);
  });
}
