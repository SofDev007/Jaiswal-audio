// Recently played songs: a song streamed start to finish (no skipping ahead)
// is kept, up to 300 MB; the least recently played go first. Played again,
// it comes from the phone and uses no data.
//
// How: the player streams through a tiny server on this phone (127.0.0.1
// only, secret random links), which passes the bytes on at the player's own
// pace and saves a copy. mpv can't record by itself (the Android audio
// libmpv has no muxers).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SongCache {
  SongCache.at(this._dir, {this.maxBytes = 300 << 20});

  static SongCache? _instance;

  static Future<SongCache> get instance async => _instance ??= SongCache.at(
      Directory(p.join((await getApplicationCacheDirectory()).path, 'songs')));

  /// Off for this run when the player couldn't use the server on this phone.
  static bool disabled = false;

  final Directory _dir;
  final int maxBytes;
  HttpServer? _server;
  final _links = LinkedHashMap<String, _Link>();
  final _asked = <String>{};
  final _rand = Random.secure();

  File _file(String trackId) => File(
      p.join(_dir.path, '${sha1.convert(utf8.encode(trackId))}.song'));

  /// The saved copy of [trackId], marked as just played; null if none.
  File? lookup(String trackId) {
    final f = _file(trackId);
    if (!f.existsSync()) return null;
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return f;
  }

  /// A link on this phone that streams [upstream] (with [headers]) and saves
  /// it for [trackId] when it is read to the end.
  Future<Uri> tee(
      String trackId, Uri upstream, Map<String, String>? headers) async {
    final server = _server ??= await _start();
    final token = [
      for (var i = 0; i < 16; i++) _rand.nextInt(256).toRadixString(16)
    ].join('-');
    _links[token] = _Link(trackId, upstream, headers ?? const {});
    if (_links.length > 64) _links.remove(_links.keys.first);
    return Uri(
        scheme: 'http', host: '127.0.0.1', port: server.port, path: '/$token');
  }

  /// Whether the player ever reached [link] (false: it couldn't connect).
  bool wasAsked(Uri link) => _asked.contains(link.path.substring(1));

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) => unawaited(_serve(r)));
    return s;
  }

  Future<void> _serve(HttpRequest req) async {
    final token = req.uri.path.substring(1);
    final link = _links[token];
    final res = req.response;
    if (link == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    _asked.add(token);
    final client = HttpClient()..autoUncompress = false;
    IOSink? part;
    File? partFile;
    var ok = false;
    try {
      final up = await client.openUrl(req.method, link.upstream);
      req.headers.forEach((k, v) {
        if (const {'host', 'connection', 'accept-encoding'}.contains(k)) {
          return;
        }
        up.headers.set(k, v);
      });
      link.headers.forEach(up.headers.set);
      final upRes = await up.close();

      res.statusCode = upRes.statusCode;
      res.contentLength = upRes.contentLength;
      for (final h in const ['content-type', 'content-range', 'accept-ranges']) {
        final v = upRes.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }

      // Saved only when this request is the whole song from its start.
      final range = req.headers.value('range')?.replaceAll(' ', '');
      final whole = req.method == 'GET' &&
          upRes.contentLength > 0 &&
          (upRes.statusCode == HttpStatus.ok ||
              (upRes.statusCode == HttpStatus.partialContent &&
                  (range == null || range == 'bytes=0-')));
      if (whole) {
        await _dir.create(recursive: true);
        partFile = File('${_file(link.trackId).path}.$token.part');
        part = partFile.openWrite();
      }
      var got = 0;
      // addStream reads the source only as fast as the player reads, and
      // stops it when the player hangs up (skip, seek, stop).
      await res.addStream(upRes.map((chunk) {
        part?.add(chunk);
        got += chunk.length;
        return chunk;
      }));
      await res.close();
      ok = whole && got == upRes.contentLength;
    } catch (e) {
      log('Stream ended early: $e', name: 'SongCache');
      try {
        await res.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
      await part?.close();
      if (partFile != null) {
        try {
          if (ok) {
            final done = _file(link.trackId);
            if (done.existsSync()) done.deleteSync();
            partFile.renameSync(done.path);
            _trim();
          } else {
            partFile.deleteSync();
          }
        } catch (e) {
          log('Saving failed: $e', name: 'SongCache');
        }
      }
    }
  }

  /// Least recently played first, until the cache fits in [maxBytes].
  void _trim() {
    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.song'))
        .map((f) => (f, f.statSync()))
        .toList()
      ..sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var total = files.fold<int>(0, (s, f) => s + f.$2.size);
    for (final (f, st) in files) {
      if (total <= maxBytes) break;
      try {
        f.deleteSync();
        total -= st.size;
      } catch (_) {}
    }
  }
}

class _Link {
  const _Link(this.trackId, this.upstream, this.headers);
  final String trackId;
  final Uri upstream;
  final Map<String, String> headers;
}
