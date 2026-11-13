// Merging this phone's music with the account's: nothing lost, no doubles,
// deletions spread, re-adds win.

import 'dart:convert';

import 'package:Bloomee/services/account/sync.dart' show keepLocalFiles, packSyncData, unpackSyncData;
import 'package:Bloomee/services/account/sync_merge.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map t(String id) => {'id': id, 'title': id};
List<String> ids(Map lib, String name) =>
    [for (final x in (lib['p'][name]['t'] as List)) x['id'] as String];

void main() {
  const now = 1000000000000;

  test('songs from both copies are kept, newer copy decides the order', () {
    final phone = {
      'p': {'Mix': {'u': now - 10, 't': [t('a'), t('b')]}}
    };
    final account = {
      'p': {'Mix': {'u': now - 5, 't': [t('c'), t('a')]}}
    };
    final m = mergeLibrary(phone, account, now);
    expect(ids(m, 'Mix'), ['c', 'a', 'b']);
  });

  test('a first sign-in merges, nothing on the phone is lost', () {
    final phone = {
      'p': {
        'Sune': {'u': 1, 't': [t('a')]},
        'Liked': {'u': 1, 't': [t('l')]},
      }
    };
    final m = mergeLibrary(phone, const {}, now);
    expect(m['p'].keys, containsAll(['Sune', 'Liked']));
    expect(ids(mergeLibrary(m, phone, now), 'Sune'), ['a'], reason: 'no doubles');
  });

  test('a removed song stays removed on the other phone', () {
    final phoneA = {
      'p': {'Mix': {'u': now - 1, 't': [t('a')]}},
      'r': {'Mix': {'b': now - 1}},
    };
    final phoneB = {
      'p': {'Mix': {'u': now - 100, 't': [t('a'), t('b')]}}
    };
    expect(ids(mergeLibrary(phoneB, phoneA, now), 'Mix'), ['a']);
  });

  test('a song added again after its removal comes back', () {
    final m = mergeLibrary({
      'p': {'Mix': {'u': now, 't': [t('b')]}},
      'r': {'Mix': {'b': now - 50}},
      'a': {'Mix': {'b': now - 10}},
    }, const {}, now);
    expect(ids(m, 'Mix'), ['b']);
  });

  test('a deleted playlist is deleted everywhere, a newer one survives', () {
    final deleter = {
      'p': {},
      'x': {'Old': now - 10, 'Again': now - 10},
    };
    final other = {
      'p': {
        'Old': {'u': now - 100, 't': [t('a')]},
        'Again': {'u': now - 1, 't': [t('z')]}, // made again later
      }
    };
    final m = mergeLibrary(other, deleter, now);
    expect(m['p'].containsKey('Old'), isFalse);
    expect(m['p'].containsKey('Again'), isTrue);
  });

  test('deletion records older than 30 days are dropped', () {
    final m = mergeLibrary({
      'p': {},
      'x': {'Ancient': now - syncKeepMs - 1, 'Recent': now - 1},
    }, const {}, now);
    expect(m['x'].keys, ['Recent']);
  });

  test('history keeps the 50 newest plays of both phones, no doubles', () {
    final a = [for (var i = 0; i < 40; i++) {'at': i * 2, 't': t('a$i')}];
    final b = [
      for (var i = 0; i < 40; i++) {'at': i * 2 + 1, 't': t('b$i')},
      a.first, // already on both
    ];
    final m = mergeHistory(a, b);
    expect(m.length, 50);
    expect(m.first['at'], 79);
    expect(m.map((e) => '${e['t']['id']}@${e['at']}').toSet().length, 50);
  });

  test("this phone's local-file songs stay where they were", () {
    Track tr(String id) => Track(
        id: id,
        title: id,
        artists: const [],
        thumbnail: const Artwork(url: '', layout: ImageLayout.square),
        isExplicit: false);
    final current = [tr('yt::a'), tr('local::f1'), tr('yt::b'), tr('local::f2')];
    final synced = [tr('yt::b'), tr('yt::c'), tr('yt::a')];
    expect(keepLocalFiles(synced, current).map((t) => t.id),
        ['yt::b', 'local::f2', 'yt::c', 'yt::a', 'local::f1']);
  });

  test('packed sync data comes back the same and much smaller', () {
    final lib = {
      'p': {
        'Mix': {
          'u': 1,
          't': [
            for (var i = 0; i < 300; i++)
              {
                'id': 'content-resolver.bloomfactory.ytmusic::$i',
                'thumbnail': {
                  'url': 'https://yt3.googleusercontent.com/abcdefghijklmnop$i=w120',
                  'url_high': 'https://yt3.googleusercontent.com/abcdefghijklmnop$i=w576',
                }
              }
          ]
        }
      }
    };
    final packed = packSyncData(lib);
    expect(unpackSyncData(packed), lib);
    expect(unpackSyncData(lib), lib, reason: 'older unpacked data still reads');
    expect(jsonEncode(packed).length, lessThan(jsonEncode(lib).length ~/ 4));
  });
}
