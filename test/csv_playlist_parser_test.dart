// Phase 2: CSV playlist parsing.
//
// Run with: flutter test test/csv_playlist_parser_test.dart

import 'package:Bloomee/services/csv_playlist_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Current Exportify header (abridged to the columns that matter plus a few
// it doesn't use, to check they're ignored).
const _exportifyHeader =
    '"Track URI","Track Name","Artist URI(s)","Artist Name(s)","Album URI",'
    '"Album Name","Album Release Date","Track Duration (ms)","Explicit",'
    '"Popularity","Added By","Added At"';

String _exportifyRow(String id, String title, String artists, String album,
        int ms, {bool explicit = false}) =>
    '"spotify:track:$id","$title","spotify:artist:x","$artists",'
    '"spotify:album:y","$album","2020-01-01","$ms","$explicit","50","",'
    '"2024-01-01T00:00:00Z"';

const _idA = '0VjIjW4GlUZAMYd2vXMi3b';
const _idB = '4uLU6hMCjMI75M1A2tKUQC';
const _idC = '7qiZfU4dY1lWllzX7mPBI3';

void main() {
  group('Exportify export', () {
    test('reads titles, artists, album, duration, explicit and Spotify IDs',
        () {
      final csv = [
        _exportifyHeader,
        _exportifyRow(_idA, 'Blinding Lights', 'The Weeknd', 'After Hours',
            200040),
        _exportifyRow(_idB, 'Hello, Goodbye - Remastered 2009',
            r'The Beatles', 'Magical Mystery Tour', 208000),
        _exportifyRow(_idC, 'EARFQUAKE', r'Tyler\, The Creator,Playboi Carti',
            'IGOR', 190066,
            explicit: true),
      ].join('\n');

      final r = parseCsvPlaylist(csv);
      expect(r.skipped, isEmpty);
      expect(r.tracks.map((t) => t.title), [
        'Blinding Lights',
        'Hello, Goodbye - Remastered 2009', // comma inside a quoted field
        'EARFQUAKE',
      ]);
      final earfquake = r.tracks[2];
      expect(earfquake.artists, ['Tyler, The Creator', 'Playboi Carti']);
      expect(earfquake.albumTitle, 'IGOR');
      expect(earfquake.durationMs, BigInt.from(190066));
      expect(earfquake.isExplicit, isTrue);
      expect(earfquake.sourceId, _idC);
      expect(earfquake.url, 'https://open.spotify.com/track/$_idC');
      expect(r.tracks[0].isExplicit, isFalse);
    });

    test('older Exportify columns ("Spotify ID", "Duration (ms)")', () {
      const csv = 'Spotify ID,Artist IDs,Track Name,Album Name,'
          'Artist Name(s),Release Date,Duration (ms)\n'
          '$_idA,x,Blinding Lights,After Hours,The Weeknd,2020,200040\n';
      final t = parseCsvPlaylist(csv).tracks.single;
      expect(t.title, 'Blinding Lights');
      expect(t.artists, ['The Weeknd']);
      expect(t.durationMs, BigInt.from(200040));
      expect(t.sourceId, _idA);
    });
  });

  group('other exporters', () {
    test('TuneMyMusic-style columns, with the playlist name', () {
      const csv = 'Track name,Artist name,Album,Playlist name,Type,ISRC\n'
          'Kesariya,Arijit Singh,Brahmastra,Road Trip,Playlist,INX\n'
          'Tum Hi Ho,Arijit Singh,Aashiqui 2,Road Trip,Playlist,INY\n';
      final r = parseCsvPlaylist(csv);
      expect(r.playlistName, 'Road Trip');
      expect(r.tracks.map((t) => t.title), ['Kesariya', 'Tum Hi Ho']);
      expect(r.tracks.first.albumTitle, 'Brahmastra');
    });

    test('Excel-style semicolon delimiter, m:ss duration', () {
      const csv = 'Title;Artist;Album;Duration\r\n'
          'Clocks;Coldplay;A Rush of Blood to the Head;5:07\r\n';
      final t = parseCsvPlaylist(csv).tracks.single;
      expect(t.title, 'Clocks');
      expect(t.artists, ['Coldplay']);
      expect(t.durationMs, BigInt.from(307000));
    });

    test('only a title column is required', () {
      final r = parseCsvPlaylist('name\nIntro\nOutro\n');
      expect(r.tracks.map((t) => t.title), ['Intro', 'Outro']);
      expect(r.tracks.first.artists, isEmpty);
      expect(r.tracks.first.durationMs, isNull);
    });

    test('a bare number under "Duration" is not guessed at', () {
      final t = parseCsvPlaylist('Title,Duration\nSong,225\n').tracks.single;
      expect(t.durationMs, isNull);
    });
  });

  group('encoding and CSV syntax', () {
    test('UTF-8 BOM, CRLF and non-Latin text', () {
      const csv = '﻿Track Name,Artist Name(s)\r\n'
          'तुम ही हो,अरिजीत सिंह\r\n'
          '夜に駆ける,YOASOBI\r\n';
      final r = parseCsvPlaylist(csv);
      expect(r.tracks.map((t) => t.title), ['तुम ही हो', '夜に駆ける']);
      expect(r.tracks.first.artists, ['अरिजीत सिंह']);
    });

    test('doubled quotes and newlines inside quoted fields', () {
      const csv = 'Track Name,Artist Name(s)\n'
          '"Say ""Hello""",Adele\n'
          '"Two\nLines",Someone\n'
          'After,Third\n';
      final r = parseCsvPlaylist(csv);
      expect(r.tracks.map((t) => t.title),
          ['Say "Hello"', 'Two\nLines', 'After']);
    });

    test('row numbers in reports follow file lines across embedded newlines',
        () {
      const csv = 'Track Name,Artist Name(s)\n' // line 1
          '"Multi\nline",A\n' // lines 2-3
          ',B\n'; // line 4: no title
      final r = parseCsvPlaylist(csv);
      expect(r.skipped, [const CsvSkippedRow(4, CsvSkipReason.missingTitle)]);
    });

    test('rows shorter than the header still import', () {
      final t = parseCsvPlaylist('Track Name,Artist Name(s),Album Name\n'
              'Short,Band\n')
          .tracks
          .single;
      expect(t.title, 'Short');
      expect(t.albumTitle, isNull);
    });
  });

  group('malformed rows and duplicates', () {
    test('missing titles are skipped with their line; blank lines ignored',
        () {
      const csv = 'Track Name,Artist Name(s)\n'
          'One,A\n'
          '\n'
          ',B\n'
          '   ,C\n'
          'Two,D\n';
      final r = parseCsvPlaylist(csv);
      expect(r.tracks.map((t) => t.title), ['One', 'Two']);
      expect(r.skipped, const [
        CsvSkippedRow(4, CsvSkipReason.missingTitle),
        CsvSkippedRow(5, CsvSkipReason.missingTitle),
      ]);
    });

    test('an unclosed quote keeps the rows before it', () {
      const csv = 'Track Name,Artist Name(s)\n'
          'Fine,A\n'
          '"Broken,B\n'
          'Swallowed,C\n';
      final r = parseCsvPlaylist(csv);
      expect(r.tracks.map((t) => t.title), ['Fine']);
      expect(r.skipped,
          const [CsvSkippedRow(3, CsvSkipReason.unterminatedQuote)]);
    });

    test('duplicates by Spotify ID or title + artists keep the first row',
        () {
      final csv = [
        _exportifyHeader,
        _exportifyRow(_idA, 'Blinding Lights', 'The Weeknd', 'After Hours', 1),
        _exportifyRow(_idB, 'Save Your Tears', 'The Weeknd', 'After Hours', 1),
        _exportifyRow(_idA, 'Blinding Lights', 'The Weeknd', 'Single', 1),
      ].join('\n');
      final r = parseCsvPlaylist(csv);
      expect(r.tracks.map((t) => t.title),
          ['Blinding Lights', 'Save Your Tears']);
      expect(r.skipped, const [
        CsvSkippedRow(4, CsvSkipReason.duplicate, duplicateOfLine: 2),
      ]);

      final byName = parseCsvPlaylist('Track Name,Artist Name(s)\n'
          'Song,Band\n'
          'song ,  BAND\n'
          'Song,Other Band\n');
      expect(byName.tracks.map((t) => t.artists.single), ['Band', 'Other Band']);
      expect(byName.skipped.single.duplicateOfLine, 2);
    });

    test('same title without artists is not treated as a duplicate', () {
      final r = parseCsvPlaylist('Track Name\nIntro\nIntro\n');
      expect(r.tracks, hasLength(2));
      expect(r.skipped, isEmpty);
    });

    test('order is the file order', () {
      final rows = [for (var i = 0; i < 300; i++) 'Song $i,Artist $i'];
      final r =
          parseCsvPlaylist('Track Name,Artist Name(s)\n${rows.join('\n')}');
      expect(r.tracks.map((t) => t.title),
          [for (var i = 0; i < 300; i++) 'Song $i']);
    });
  });

  group('unusable files', () {
    test('no track name column', () {
      expect(() => parseCsvPlaylist('Artist,Album\nA,B\n'),
          throwsA(isA<CsvPlaylistFormatException>()));
    });

    test('empty file', () {
      expect(() => parseCsvPlaylist(''),
          throwsA(isA<CsvPlaylistFormatException>()));
      expect(() => parseCsvPlaylist('\n\n'),
          throwsA(isA<CsvPlaylistFormatException>()));
    });

    test('header only gives no tracks', () {
      final r = parseCsvPlaylist('Track Name,Artist Name(s)\n');
      expect(r.tracks, isEmpty);
    });
  });

  group('spotifyTrackId', () {
    test('accepts URIs, URLs and bare IDs', () {
      expect(spotifyTrackId('spotify:track:$_idA'), _idA);
      expect(spotifyTrackId('https://open.spotify.com/track/$_idA?si=abc'),
          _idA);
      expect(
          spotifyTrackId('https://open.spotify.com/intl-de/track/$_idA'), _idA);
      expect(spotifyTrackId(_idA), _idA);
    });

    test('rejects local files and other kinds', () {
      expect(spotifyTrackId('spotify:local:Artist:Album:Title:200'), isNull);
      expect(spotifyTrackId('spotify:album:$_idA'), isNull);
      expect(spotifyTrackId(''), isNull);
    });
  });

  test('splitArtists handles escapes and semicolons', () {
    expect(splitArtists(r'Tyler\, The Creator, Kali Uchis'),
        ['Tyler, The Creator', 'Kali Uchis']);
    expect(splitArtists('A; B'), ['A', 'B']);
    expect(splitArtists(''), isEmpty);
  });
}
