// V2.0 security: a plugin file is installed only if it matches the
// fingerprint (sha256) in the plugin list.

import 'dart:convert';

import 'package:Bloomee/plugins/models/plugin_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

RemotePluginModel _plugin(String sha) => RemotePluginModel.fromJson({
      'id': 'content-resolver.test',
      'name': 'test',
      'download_url': 'https://example.com/test.bex',
      if (sha.isNotEmpty) 'sha256': sha,
    });

void main() {
  final file = utf8.encode('the real plugin file');
  final good = sha256.convert(file).toString();

  test('the right file passes', () {
    expect(() => _plugin(good).verifyFile(file), returnsNormally);
    expect(() => _plugin(good.toUpperCase()).verifyFile(file), returnsNormally);
  });

  test('a swapped or cut-off file is refused', () {
    expect(() => _plugin(good).verifyFile(utf8.encode('something else')),
        throwsA(isA<PluginFileMismatch>()));
    expect(() => _plugin(good).verifyFile(file.sublist(0, 5)),
        throwsA(isA<PluginFileMismatch>()));
  });

  test('a list without a fingerprint still installs (older lists)', () {
    expect(() => _plugin('').verifyFile(file), returnsNormally);
  });
}
