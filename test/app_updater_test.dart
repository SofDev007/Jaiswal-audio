// The update notice lists every full release the user skipped, newest first.

import 'package:Bloomee/services/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final releases = [
    {'tag_name': 'v2.0.0+39', 'prerelease': true, 'body': 'test build'},
    {'tag_name': 'v2.0.0+38', 'body': 'Jam'},
    {'tag_name': 'v2.0.0+37', 'body': 'First run\n'},
    {'tag_name': 'v2.0.0+36', 'body': 'Updater', 'draft': true},
    {'tag_name': 'v2.0.0+35', 'body': 'Sync'},
  ];

  test('someone on 35 sees 38 and 37, not drafts or pre-releases', () {
    expect(notesSince(releases, 35),
        'JARX 2.0.0 (build 38)\nJam\n\nJARX 2.0.0 (build 37)\nFirst run');
  });

  test('up to date: nothing', () {
    expect(notesSince(releases, 38), '');
  });

  test('build number from a tag', () {
    expect(buildOfTag('v2.0.0+36'), 36);
    expect(buildOfTag('v2.0.0'), 0);
  });

  group('compulsory update', () {
    final rel = [
      {'tag_name': 'v2.0.0+41', 'body': 'Polish'},
      {'tag_name': 'v2.0.0+40', 'prerelease': true, 'body': requiredMarker},
      {'tag_name': 'v2.0.0+39', 'body': 'Fix\n$requiredMarker'},
      {'tag_name': 'v2.0.0+38', 'body': '$requiredMarker\nOld fix'},
    ];

    test('someone on 37 must install (the newest required is 39)', () {
      expect(requiredBuildIn(rel, 37), 39);
    });

    test('past the required build: free', () {
      expect(requiredBuildIn(rel, 39), 0);
    });

    test('pre-releases and unmarked releases never force', () {
      expect(requiredBuildIn([rel[0], rel[1]], 37), 0);
    });

    test('the marker never shows in the notes', () {
      expect(notesSince(rel, 38),
          'JARX 2.0.0 (build 41)\nPolish\n\nJARX 2.0.0 (build 39)\nFix');
    });
  });
}
