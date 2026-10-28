import 'package:Bloomee/screens/widgets/marquee_overflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _offset(WidgetTester t) =>
    t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!
        .offset;

Widget _box(String text) => MaterialApp(
      home: Center(
        child: SizedBox(width: 100, child: MarqueeOverflow(child: Text(text))),
      ),
    );

void main() {
  testWidgets('long text scrolls, short text stays still', (t) async {
    await t.pumpWidget(_box('A very long song title that cannot fit here'));
    await t.pump(const Duration(seconds: 2)); // initial pause
    await t.pump(const Duration(milliseconds: 500)); // animation frames
    expect(_offset(t), greaterThan(0));

    await t.pumpWidget(_box('Hi'));
    await t.pump(const Duration(seconds: 3));
    expect(_offset(t), 0);
    await t.pumpWidget(const SizedBox()); // stop the loop
    await t.pump(const Duration(seconds: 30));
  });
}
