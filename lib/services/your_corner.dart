// "Your corner" (tap your photo on Home): this month's listening, top 5
// artists and songs, and a silly comparison of the minutes.

import 'package:Bloomee/services/player/listening_time.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// The month Your corner shows: this one, except in its first 3 days when
/// last month has something (on the 1st there's almost nothing yet).
({String label, ListeningStats stats}) cornerMonth(
    ListeningStats all, DateTime now) {
  final last = DateTime(now.year, now.month - 1);
  final lastStats = all.months[monthKey(last)];
  if (now.day <= 3 && lastStats != null && lastStats.totalMs > 0) {
    return (label: _monthNames[last.month - 1], stats: lastStats);
  }
  return (
    label: _monthNames[now.month - 1],
    stats: all.months[monthKey(now)] ?? ListeningStats(now, 0, {}),
  );
}

/// (what, minutes one of it takes, sentence with {n})
const _comparisons = [
  ('Titanic', 195, "That's {n} Titanic movies, back to back."),
  ('Sholay', 204, 'Enough to watch Sholay {n} times.'),
  ('Maggi', 2, 'That’s {n} packets of 2-minute Maggi.'),
  ('IPL', 210, 'Longer than {n} full IPL matches.'),
  ('Flight', 130, 'You could fly Mumbai to Delhi {n} times.'),
  ('Kettle', 3, 'Time to boil a kettle {n} times.'),
  ('Mahabharat', 4230, 'The whole Mahabharat serial, {n} times over.'),
  ('Charging', 90, 'Your phone could charge from 0 to 100 {n} times.'),
];

/// A silly comparison of [minutes], or null when there's too little to
/// compare. Only ones that come out between 1 and 999 are used (no
/// "0.01 Mahabharats"); which one changes with [day].
String? sillyComparison(int minutes, int day) {
  final fits = [
    for (final c in _comparisons)
      if (minutes / c.$2 >= 1 && minutes / c.$2 < 1000) c,
  ];
  if (fits.isEmpty) return null;
  final c = fits[day % fits.length];
  final n = minutes / c.$2;
  final text = n >= 10 || n == n.roundToDouble()
      ? n.round().toString()
      : n.toStringAsFixed(1);
  return c.$3.replaceAll('{n}', text);
}

/// "1 h 05 min" / "42 min".
String minutesText(int ms) {
  final m = ms ~/ 60000;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}
