import 'dart:math';

const _noInternetQuips = [
  'The internet ghosted us. Your downloads never will.',
  "Offline? Your downloads don't need Wi-Fi.",
  'No signal. The songs are stuck in traffic. Your downloads made it home though.',
];

/// The "no internet" line: one of three, picked once per app run so it
/// doesn't change every time the screen redraws.
final String noInternetQuip =
    _noInternetQuips[Random().nextInt(_noInternetQuips.length)];
