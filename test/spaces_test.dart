import 'dart:io';

import 'package:Bloomee/services/account/account.dart';
import 'package:Bloomee/services/account/spaces.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('accounts on a phone keep apart', () {
    final dir = Directory.systemTemp.createTempSync('spaces_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    // A phone from before spaces: one space, nobody's.
    Spaces.load(dir.path);
    expect(Spaces.active, Spaces.first);
    expect(Spaces.ownerOf(Spaces.first), isNull);
    expect(Spaces.key('jarxSession'), 'jarxSession'); // old keys kept

    const friend = JarxUser('7', 'f@x.com', 'Friend', '');
    const me = JarxUser('42', 'me@x.com', 'Me', '');
    Spaces.own(friend);
    expect(Spaces.spaceOf('7'), Spaces.first);
    expect(Spaces.spaceOf('42'), isNull); // me: a new space, not his

    // What Spaces.create records (the database copy needs Isar).
    File(p.join(dir.path, 'spaces.json')).writeAsStringSync(
        '{"active":"u_42","spaces":{"dbv3":{"user":${_j(friend)}},'
        '"u_42":{"user":${_j(me)}}}}');
    File(p.join(dir.path, 'u_42.isar')).writeAsStringSync('');
    Spaces.load(dir.path);
    expect(Spaces.active, 'u_42');
    expect(Spaces.key('jarxSession'), 'jarxSession@u_42');
    expect([for (final (s, u) in Spaces.accounts) '$s=${u.name}'],
        ['dbv3=Friend', 'u_42=Me']);

    Spaces.remove('u_42'); // the open space can't go
    expect(Spaces.spaceOf('42'), 'u_42');

    // Back on the friend's space, he takes my account off his phone.
    File(p.join(dir.path, 'spaces.json')).writeAsStringSync(
        '{"active":"dbv3","spaces":{"dbv3":{"user":${_j(friend)}},'
        '"u_42":{"user":${_j(me)}}}}');
    Spaces.load(dir.path);
    Spaces.remove('u_42');
    expect(Spaces.spaceOf('42'), isNull);
    expect(File(p.join(dir.path, 'u_42.isar')).existsSync(), isFalse);

    // A broken or missing active space falls back to the first one.
    File(p.join(dir.path, 'spaces.json'))
        .writeAsStringSync('{"active":"gone","spaces":{}}');
    Spaces.load(dir.path);
    expect(Spaces.active, Spaces.first);
  });
}

String _j(JarxUser u) =>
    '{"id":"${u.id}","email":"${u.email}","name":"${u.name}","photo":""}';
