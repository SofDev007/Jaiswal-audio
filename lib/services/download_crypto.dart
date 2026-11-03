import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloaded songs are stored encrypted, under a random name ending in
/// [extension], so they can't be played or shared outside JARX. Android only
/// (the cipher is DownloadCrypto.kt behind channel "jarx/crypto"); elsewhere
/// downloads stay plain files.
///
/// To play one, [playableCopy] decrypts it into the app's private cache,
/// which other apps and a connected PC can't read.
class DownloadCrypto {
  static const _channel = MethodChannel('jarx/crypto');
  static const extension = '.jarx';

  /// Decrypted songs kept in the cache, so replays and the next track in the
  /// queue don't decrypt again.
  static const _keepPlayable = 3;

  static bool get supported => Platform.isAndroid;

  static bool isEncrypted(String fileName) => fileName.endsWith(extension);

  /// Replaces the download [mediaId] at [plainPath] by an encrypted copy
  /// under a random name in the same folder. The plain file is deleted only
  /// after the record points at the copy, so nothing is lost on a crash.
  static Future<void> encryptDownload(
      DownloadDAO dao, String mediaId, String plainPath) async {
    final name = '${_randomCode()}$extension';
    await _channel.invokeMethod('encrypt',
        {'src': plainPath, 'dst': p.join(p.dirname(plainPath), name)});
    await dao.setDownloadFileName(mediaId, name);
    await File(plainPath).delete();
  }

  static final _decrypting = <String, Future<String>>{};

  /// Path of a playable (decrypted) copy of [encryptedPath].
  static Future<String> playableCopy(String encryptedPath) =>
      _decrypting[encryptedPath] ??=
          _playableCopy(encryptedPath).whenComplete(() {
        // A block, not `=> remove(...)`: remove returns this very future,
        // and whenComplete would wait for it forever.
        _decrypting.remove(encryptedPath);
      });

  static Future<String> _playableCopy(String encryptedPath) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'play'));
    await dir.create(recursive: true);
    // Named "<code>.<format>": the player wants a real audio file name. The
    // format is sniffed from the decrypted bytes, so the stored name never
    // reveals it.
    final code = p.basenameWithoutExtension(encryptedPath);
    File? out;
    await for (final e in dir.list()) {
      if (e is File &&
          !e.path.endsWith('.part') &&
          p.basenameWithoutExtension(e.path) == code) {
        out = e;
      }
    }
    if (out == null) {
      final raw = File(p.join(dir.path, code));
      await _channel
          .invokeMethod('decrypt', {'src': encryptedPath, 'dst': raw.path});
      out = await raw.rename('${raw.path}.${await _sniffExtension(raw)}');
    }
    await out.setLastModified(DateTime.now());
    await _prune(dir, keep: out.path);
    return out.path;
  }

  /// Deletes all but the [_keepPlayable] most recently used copies.
  static Future<void> _prune(Directory dir, {required String keep}) async {
    final files = await dir
        .list()
        .where((e) => e is File && !e.path.endsWith('.part'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final f in files.skip(_keepPlayable)) {
      if (f.path != keep) await f.delete().catchError((_) => f);
    }
  }

  /// Encrypts downloads made before encryption existed. Only files in JARX's
  /// own download folders (phone storage or SD card), never Local music.
  static Future<void> encryptExisting(DownloadDAO dao) async {
    if (!supported) return;
    final ours = [
      for (final d in await getExternalStorageDirectories(
              type: StorageDirectory.downloads) ??
          const <Directory>[])
        p.normalize(d.path),
    ];
    for (final r in await dao.getValidDownloads()) {
      if (isEncrypted(r.fileName) ||
          !ours.any(
              (d) => p.equals(d, r.filePath) || p.isWithin(d, r.filePath))) {
        continue;
      }
      try {
        await encryptDownload(dao, r.mediaId, p.join(r.filePath, r.fileName));
        log('Encrypted ${r.fileName}', name: 'DownloadCrypto');
      } catch (e) {
        log('Could not encrypt ${r.fileName}: $e', name: 'DownloadCrypto');
      }
    }
  }

  static Future<String> _sniffExtension(File f) async {
    final h = <int>[];
    await for (final chunk in f.openRead(0, 12)) {
      h.addAll(chunk);
    }
    String at(int i, int n) =>
        h.length >= i + n ? String.fromCharCodes(h.sublist(i, i + n)) : '';
    if (at(4, 4) == 'ftyp') return 'm4a';
    if (at(0, 3) == 'ID3' ||
        (h.length > 1 && h[0] == 0xFF && h[1] & 0xE0 == 0xE0)) {
      return 'mp3';
    }
    if (at(0, 4) == 'OggS') return 'ogg';
    if (at(0, 4) == 'fLaC') return 'flac';
    if (at(0, 4) == 'RIFF') return 'wav';
    if (h.length > 1 && h[0] == 0x1A && h[1] == 0x45) return 'webm';
    return 'm4a';
  }

  static String _randomCode() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
