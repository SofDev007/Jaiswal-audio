/// Reads a playlist exported as CSV (Exportify, Spotify-style exports,
/// TuneMyMusic, Soundiiz and similar) into import tracks, in file order.
///
/// Pure: no I/O. Columns are found by header name, so column order and extra
/// columns don't matter; only a track-name column is required.
library csv_playlist_parser;

import 'package:Bloomee/src/rust/api/plugin/models.dart';

/// Why a row was left out of the import.
enum CsvSkipReason {
  /// The track-name cell is empty.
  missingTitle,

  /// A quoted field never closes, so the rest of the file is unreadable.
  unterminatedQuote,

  /// Same track as an earlier row ([CsvSkippedRow.duplicateOfLine]).
  duplicate,
}

class CsvSkippedRow {
  /// 1-based line where the row starts in the file.
  final int line;
  final CsvSkipReason reason;
  final int? duplicateOfLine;

  const CsvSkippedRow(this.line, this.reason, {this.duplicateOfLine});

  @override
  bool operator ==(Object other) =>
      other is CsvSkippedRow &&
      other.line == line &&
      other.reason == reason &&
      other.duplicateOfLine == duplicateOfLine;

  @override
  int get hashCode => Object.hash(line, reason, duplicateOfLine);

  @override
  String toString() =>
      'CsvSkippedRow($line, $reason${duplicateOfLine == null ? '' : ' of $duplicateOfLine'})';
}

class CsvPlaylist {
  /// In file order, duplicates removed.
  final List<ImportTrackItem> tracks;
  final List<CsvSkippedRow> skipped;

  /// From a "Playlist name" column, when the export has one.
  final String? playlistName;

  const CsvPlaylist(this.tracks, this.skipped, this.playlistName);
}

/// The file can't be read as a playlist at all.
class CsvPlaylistFormatException implements Exception {
  final String message;
  const CsvPlaylistFormatException(this.message);

  @override
  String toString() => 'CsvPlaylistFormatException: $message';
}

// Header names, lowercased. The first column matching a list wins.
const _titleHeaders = [
  'track name', 'track title', 'title', 'song name', 'song', 'name', 'track',
];
const _artistHeaders = [
  'artist name(s)', 'artist names', 'artist name', 'artists', 'artist',
];
const _albumHeaders = ['album name', 'album title', 'album'];
const _durationMsHeaders = [
  'track duration (ms)', 'duration (ms)', 'duration_ms', 'duration ms',
];
const _durationClockHeaders = ['duration', 'length', 'time'];
const _idHeaders = [
  'track uri', 'spotify uri', 'uri', 'spotify id', 'spotify - id',
  'spotify track id', 'track id', 'id',
];
const _urlHeaders = ['track url', 'spotify url', 'url', 'link'];
const _explicitHeaders = ['explicit'];
const _playlistHeaders = ['playlist name', 'playlist'];

/// Parses [text] (already decoded; a UTF-8 BOM is ignored).
///
/// Throws [CsvPlaylistFormatException] when there is no header row or no
/// track-name column.
CsvPlaylist parseCsvPlaylist(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final records = parseCsvRecords(text, delimiter: _detectDelimiter(text));
  final rows = records.where((r) => r.fields.any((f) => f.trim().isNotEmpty));
  if (rows.isEmpty) {
    throw const CsvPlaylistFormatException('The file is empty.');
  }

  final header = rows.first;
  final names = [
    for (final h in header.fields) h.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
  ];
  int col(List<String> wanted) {
    for (final w in wanted) {
      final i = names.indexOf(w);
      if (i >= 0) return i;
    }
    return -1;
  }

  final titleCol = col(_titleHeaders);
  if (titleCol < 0) {
    throw const CsvPlaylistFormatException('No track name column.');
  }
  final artistCol = col(_artistHeaders);
  final albumCol = col(_albumHeaders);
  final durationMsCol = col(_durationMsHeaders);
  final durationClockCol = col(_durationClockHeaders);
  final idCol = col(_idHeaders);
  final urlCol = col(_urlHeaders);
  final explicitCol = col(_explicitHeaders);
  final playlistCol = col(_playlistHeaders);

  final tracks = <ImportTrackItem>[];
  final skipped = <CsvSkippedRow>[];
  final firstLineByKey = <String, int>{};
  String? playlistName;

  for (final row in rows.skip(1)) {
    String cell(int i) => i >= 0 && i < row.fields.length ? row.fields[i].trim() : '';

    if (!row.complete) {
      skipped.add(CsvSkippedRow(row.line, CsvSkipReason.unterminatedQuote));
      continue;
    }
    final title = cell(titleCol);
    if (title.isEmpty) {
      skipped.add(CsvSkippedRow(row.line, CsvSkipReason.missingTitle));
      continue;
    }

    final artists = splitArtists(cell(artistCol));
    final spotifyId = spotifyTrackId(cell(idCol)) ?? spotifyTrackId(cell(urlCol));
    // Same Spotify ID, or same title and artists. A title alone isn't enough:
    // two artist-less "Intro" rows may be different songs.
    final key = spotifyId ??
        (artists.isEmpty
            ? null
            : '${_norm(title)}|${artists.map(_norm).join(',')}');
    final firstLine = firstLineByKey[key];
    if (key != null && firstLine != null) {
      skipped.add(CsvSkippedRow(row.line, CsvSkipReason.duplicate,
          duplicateOfLine: firstLine));
      continue;
    }
    if (key != null) firstLineByKey[key] = row.line;

    final durationMs = int.tryParse(cell(durationMsCol)) ??
        _clockToMs(cell(durationClockCol));
    final album = cell(albumCol);
    final explicit = cell(explicitCol).toLowerCase();
    playlistName ??= cell(playlistCol).isEmpty ? null : cell(playlistCol);

    tracks.add(ImportTrackItem(
      title: title,
      artists: artists,
      albumTitle: album.isEmpty ? null : album,
      durationMs: durationMs != null && durationMs > 0
          ? BigInt.from(durationMs)
          : null,
      isExplicit: explicit == 'true' || explicit == 'yes' || explicit == '1',
      url: spotifyId == null ? null : 'https://open.spotify.com/track/$spotifyId',
      sourceId: spotifyId,
    ));
  }

  return CsvPlaylist(tracks, skipped, playlistName);
}

/// Artists from one cell. Exportify joins them with "," and escapes commas
/// inside a name as "\,"; some exporters use ";".
List<String> splitArtists(String cell) {
  return cell
      .split(RegExp(r'(?<!\\)[,;]'))
      .map((a) => a.replaceAll(r'\,', ',').replaceAll(r'\;', ';').trim())
      .where((a) => a.isNotEmpty)
      .toList(growable: false);
}

final _bareId = RegExp(r'^[A-Za-z0-9]{22}$');
final _uriId = RegExp(r'^spotify:track:([A-Za-z0-9]{22})$');
final _urlId = RegExp(r'open\.spotify\.com/(?:intl-[a-z]+/)?track/([A-Za-z0-9]{22})');

/// The 22-character Spotify track ID in a URI, URL or bare ID, if any.
/// Local files ("spotify:local:...") have none.
String? spotifyTrackId(String value) {
  final v = value.trim();
  if (_bareId.hasMatch(v)) return v;
  return (_uriId.firstMatch(v) ?? _urlId.firstMatch(v))?.group(1);
}

/// "3:45" or "1:02:03" → milliseconds. Bare numbers are not guessed at.
int? _clockToMs(String v) {
  final parts = v.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0)) return null;
  final secs = nums.fold<int>(0, (acc, n) => acc * 60 + n!);
  return secs * 1000;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The header line's most common separator outside quotes: ",", ";" or tab.
/// (Excel in many locales saves "CSV" with ";".)
String _detectDelimiter(String text) {
  final counts = {',': 0, ';': 0, '\t': 0};
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') quoted = !quoted;
    if (!quoted && (ch == '\n' || ch == '\r')) {
      if (counts.values.any((c) => c > 0)) break; // end of the header line
      continue;
    }
    if (!quoted && counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

class CsvRecord {
  /// 1-based line where the record starts.
  final int line;
  final List<String> fields;

  /// False when a quoted field runs to the end of the file unclosed.
  final bool complete;

  const CsvRecord(this.line, this.fields, {this.complete = true});
}

/// RFC 4180 records: quoted fields may hold the delimiter, newlines and
/// doubled quotes; CRLF, LF and CR line ends are all accepted.
List<CsvRecord> parseCsvRecords(String text, {String delimiter = ','}) {
  final records = <CsvRecord>[];
  var fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var line = 1;
  var start = 1;

  void endField() {
    fields.add(field.toString());
    field.clear();
  }

  void endRecord() {
    endField();
    records.add(CsvRecord(start, fields));
    fields = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        if (ch == '\n') line++;
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      quoted = true;
    } else if (ch == delimiter) {
      endField();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRecord();
      line++;
      start = line;
    } else {
      field.write(ch);
    }
  }

  if (quoted) {
    endField();
    records.add(CsvRecord(start, fields, complete: false));
  } else if (field.isNotEmpty || fields.isNotEmpty) {
    endRecord();
  }
  return records;
}
