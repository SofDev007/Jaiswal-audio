import 'package:Bloomee/services/account/sync.dart';
import 'package:flutter_test/flutter_test.dart';

// The 60 s check runs the full sync only when the server sent data for some
// kind (another phone changed it); timestamps alone mean nothing is new.
void main() {
  test('only timestamps: nothing new', () {
    expect(
        hasRemoteChanges({
          'library': {'updatedAt': 5},
          'history': {'updatedAt': 7},
        }),
        isFalse);
    expect(hasRemoteChanges(<String, dynamic>{}), isFalse);
    expect(hasRemoteChanges(null), isFalse);
  });

  test('data for any kind: run the full sync', () {
    expect(
        hasRemoteChanges({
          'library': {'updatedAt': 5},
          'listening:phone2': {'data': 'x', 'updatedAt': 9},
        }),
        isTrue);
  });
}
