// The in-app updater: downloads a new JARX APK with progress and opens
// Android's installer. Android checks the update is signed with the same key
// as the installed JARX before it installs anything.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AppUpdater {
  static const _channel = MethodChannel('jarx/app');

  /// Downloads [url] to the app's cache, reporting 0..1 (null while the size
  /// is unknown). Returns the saved file's path.
  static Future<String> download(String url, void Function(double?) onProgress) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/jarx_update.apk');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(total == null || total == 0 ? null : got / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }

  static Future<void> install(String path) =>
      _channel.invokeMethod('installApk', {'path': path});
}

/// A compulsory update. Put this line in a GitHub release's notes (GitHub
/// hides HTML comments) and every phone on JARX 37+ that is older than that
/// release stops playing songs until it updates.
const requiredMarker = '<!-- jarx:required -->';

/// The newest full release newer than [currentBuild] whose notes carry
/// [requiredMarker], or 0 when no update is compulsory.
int requiredBuildIn(List releases, int currentBuild) {
  var req = 0;
  for (final r in releases.cast<Map>()) {
    final b = buildOfTag('${r['tag_name']}');
    if (r['draft'] != true &&
        r['prerelease'] != true &&
        b > currentBuild &&
        b > req &&
        '${r['body'] ?? ''}'.contains(requiredMarker)) {
      req = b;
    }
  }
  return req;
}

/// A compulsory update is waiting: songs don't play, and the guided tour
/// (bell -> update -> Download/Install) shows on any play attempt.
class UpdateGate {
  /// The build the user must install, 0 for none.
  static final requiredBuild = ValueNotifier<int>(0);

  /// The Home tour (spotlight on the bell) is showing. The update in the
  /// bell list and the Download/Install button glow whenever [blocked].
  static final showingTour = ValueNotifier<bool>(false);

  static bool get blocked => requiredBuild.value > 0;

  /// Called when something tries to play while [blocked].
  static void showTour() => showingTour.value = true;
}

/// Build number from a release tag like `v2.0.0+38` (0 when missing).
int buildOfTag(String tag) => int.tryParse(tag.split('+').last) ?? 0;

/// A release notes' own first line when it only repeats the heading
/// ("JARX 2.0.0 (build 39)", "Build 37:").
final _repeatedTitle = RegExp(r'^\s*(JARX .*\(build \d+\)|build \d+\s*:?)\s*$',
    caseSensitive: false);

String _releaseName(Map r) =>
    'JARX ${'${r['tag_name']}'.replaceFirst(RegExp('^[vV]'), '').replaceFirst('+', ' (build ')})';

String _releaseDate(Map r) {
  final d = DateTime.tryParse('${r['published_at']}')?.toLocal();
  return d == null ? '' : DateFormat('d MMM yyyy').format(d);
}

/// One release: its name and date, then its notes.
String _section(Map r) {
  var lines = '${r['body'] ?? ''}'
      .replaceAll(requiredMarker, '')
      .replaceAll('\r', '')
      .trim()
      .split('\n');
  if (_repeatedTitle.hasMatch(lines.first)) lines = lines.sublist(1);
  final date = _releaseDate(r);
  final notes = lines.join('\n').trim();
  return '${_releaseName(r)}${date.isEmpty ? '' : ' · $date'}'
      '${notes.isEmpty ? '' : '\n$notes'}';
}

/// The update text: the build you have, the latest build (date and notes),
/// then any other builds you skipped. Empty when up to date.
/// [releases] is GitHub's release list; drafts and pre-releases don't count.
String notesSince(List releases, String currentVersion, int currentBuild) {
  final newer = [
    for (final r in releases.cast<Map>())
      if (r['draft'] != true &&
          r['prerelease'] != true &&
          buildOfTag('${r['tag_name']}') > currentBuild)
        r
  ]..sort((a, b) =>
      buildOfTag('${b['tag_name']}') - buildOfTag('${a['tag_name']}'));
  if (newer.isEmpty) return '';
  return [
    'Current build\nJARX $currentVersion (build $currentBuild)',
    'Latest build\n${_section(newer.first)}',
    if (newer.length > 1)
      'Also new since your build\n${newer.skip(1).map(_section).join('\n\n')}',
  ].join('\n\n');
}
