// The update text: the build you have, the latest build (date and notes),
// then the other builds you skipped.

import 'package:Bloomee/services/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Noon UTC: the same calendar day in every time zone.
  final releases = [
    {
      'tag_name': 'v2.0.0+39',
      'prerelease': true,
      'body': 'test build',
      'published_at': '2026-11-21T12:00:00Z'
    },
    {
      'tag_name': 'v2.0.0+38',
      // The notes repeat the heading on their first line: dropped.
      'body': 'JARX 2.0.0 (build 38)\r\n\r\nJam',
      'published_at': '2026-11-20T12:00:00Z'
    },
    {
      'tag_name': 'v2.0.0+37',
      'body': 'Build 37:\nFirst run\n',
      'published_at': '2026-11-19T12:00:00Z'
    },
    {'tag_name': 'v2.0.0+36', 'body': 'Updater', 'draft': true},
    {'tag_name': 'v2.0.0+35', 'body': 'Sync'},
  ];

  test('current build, then the latest, then the others skipped', () {
    expect(
        notesSince(releases, '2.0.0', 35),
        'Current build\nJARX 2.0.0 (build 35)\n\n'
        'Latest build\nJARX 2.0.0 (build 38) · 20 Nov 2026\nJam\n\n'
        'Also new since your build\n'
        'JARX 2.0.0 (build 37) · 19 Nov 2026\nFirst run');
  });

  test('one build behind: no "also new" part', () {
    expect(
        notesSince(releases, '2.0.0', 37),
        'Current build\nJARX 2.0.0 (build 37)\n\n'
        'Latest build\nJARX 2.0.0 (build 38) · 20 Nov 2026\nJam');
  });

  test('up to date: nothing', () {
    expect(notesSince(releases, '2.0.0', 38), '');
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
      expect(
          notesSince(rel, '2.0.0', 38),
          'Current build\nJARX 2.0.0 (build 38)\n\n'
          'Latest build\nJARX 2.0.0 (build 41)\nPolish\n\n'
          'Also new since your build\nJARX 2.0.0 (build 39)\nFix');
    });
  });
}
