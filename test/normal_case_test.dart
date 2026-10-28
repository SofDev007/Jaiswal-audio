import 'package:Bloomee/utils/extentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ALL-CAPS titles become Title Case, others stay', () {
    expect('TUM HI HO'.normalCase(), 'Tum Hi Ho');
    expect('DON\'T STOP (FROM "ANIMAL")'.normalCase(),
        'Don\'t Stop (From "Animal")');
    expect('DNA'.normalCase(), 'DNA');
    expect('Tum Hi Ho'.normalCase(), 'Tum Hi Ho');
    expect('iPhone LOVE'.normalCase(), 'iPhone LOVE');
    expect('तुम ही हो'.normalCase(), 'तुम ही हो');
  });
}
