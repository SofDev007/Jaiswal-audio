// The song cache keeps a song only when the player read all of it.
//
// Run with: flutter test test/song_cache_test.dart

import 'dart:io';

import 'package:Bloomee/services/player/song_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer source;
  late Directory dir;
  final song = List<int>.generate(200000, (i) => i % 251);
  final seen = <String?>[];

  setUp(() async {
    seen.clear();
    dir = await Directory.systemTemp.createTemp('songcache');
    source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    source.listen((req) async {
      seen.add(req.headers.value('x-plugin'));
      if (req.uri.path == '/big') {
        // A real-size song (16 MB), sent piece by piece.
        req.response.contentLength = 256 * 65536;
        final piece = List<int>.filled(65536, 7);
        try {
          for (var i = 0; i < 256; i++) {
            req.response.add(piece);
            await req.response.flush();
          }
          await req.response.close();
        } catch (_) {}
        return;
      }
      final range = req.headers.value('range');
      final from = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final res = req.response;
      if (range != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers
            .set('content-range', 'bytes $from-${song.length - 1}/${song.length}');
      }
      res.contentLength = song.length - from;
      res.add(song.sublist(from));
      await res.close();
    });
  });

  tearDown(() async {
    await source.close(force: true);
    await dir.delete(recursive: true);
  });

  Uri up(String name) => Uri.parse('http://127.0.0.1:${source.port}/$name');

  Future<List<int>> read(Uri link, {String? range, int? stopAfter}) async {
    final c = HttpClient();
    final req = await c.getUrl(link);
    if (range != null) req.headers.set('range', range);
    final res = await req.close();
    final got = <int>[];
    await for (final chunk in res) {
      got.addAll(chunk);
      if (stopAfter != null && got.length >= stopAfter) break;
    }
    c.close(force: true);
    return got;
  }

  // The server finishes its work just after the player has its bytes.
  Future<void> settle() => Future.delayed(const Duration(milliseconds: 200));

  test('read to the end: kept, byte for byte, with the plugin headers',
      () async {
    final cache = SongCache.at(dir);
    final link = await cache.tee('yt::a', up('a'), {'x-plugin': 'yes'});
    expect(await read(link), song);
    await settle();
    expect(cache.lookup('yt::a')!.readAsBytesSync(), song);
    expect(seen, ['yes']);
    expect(cache.wasAsked(link), isTrue);
  });

  test('from the start with "bytes=0-" counts as whole', () async {
    final cache = SongCache.at(dir);
    final link = await cache.tee('yt::b', up('b'), null);
    expect(await read(link, range: 'bytes=0-'), song);
    await settle();
    expect(cache.lookup('yt::b'), isNotNull);
  });

  // (A song short enough to pass through whole before the player hangs up
  // is complete, so it is kept; that's fine.)
  test('stopped half way: nothing kept', () async {
    final cache = SongCache.at(dir);
    final link = await cache.tee('yt::c', up('big'), null);
    await read(link, stopAfter: 100000);
    await Future.delayed(const Duration(seconds: 1));
    expect(cache.lookup('yt::c'), isNull);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty,
        reason: 'no half file left behind');
  });

  test('skipped ahead: right bytes, nothing kept', () async {
    final cache = SongCache.at(dir);
    final link = await cache.tee('yt::d', up('d'), null);
    expect(await read(link, range: 'bytes=5000-'), song.sublist(5000));
    await settle();
    expect(cache.lookup('yt::d'), isNull);
  });

  test('over the limit: the least recently played go first', () async {
    final cache = SongCache.at(dir, maxBytes: song.length * 2);
    for (final id in ['1', '2']) {
      await read(await cache.tee(id, up(id), null));
      await settle();
    }
    // "1" played again: "2" is now the oldest.
    await Future.delayed(const Duration(milliseconds: 1100));
    expect(cache.lookup('1'), isNotNull);
    await read(await cache.tee('3', up('3'), null));
    await settle();
    expect(cache.lookup('2'), isNull);
    expect(cache.lookup('1'), isNotNull);
    expect(cache.lookup('3'), isNotNull);
  });

  test('a made-up link gets nothing', () async {
    final cache = SongCache.at(dir);
    final link = await cache.tee('yt::e', up('e'), null);
    final c = HttpClient();
    final res = await (await c.getUrl(link.replace(path: '/guess'))).close();
    expect(res.statusCode, HttpStatus.notFound);
    c.close(force: true);
  });
}
