import 'package:Bloomee/utils/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a source error body never reaches the UI', () {
    const raw = 'browse: {\n "error": {\n  "code": 400,\n  "message": '
        '"Request contains an invalid argument.",\n  "status": '
        '"INVALID_ARGUMENT"\n }\n}';
    expect(friendlyError(raw, fallback: 'Could not load this artist.'),
        'Could not load this artist.');
  });

  test('offline errors say so', () {
    for (final raw in [
      "SocketException: Failed host lookup: 'music.youtube.com'",
      'error sending request for url (https://www.jiosaavn.com/api.php)',
      'ClientException with SocketException: Connection refused',
      'TimeoutException after 0:00:15.000000',
      // Seen on the phone: artist page of a downloaded song, offline.
      'WASM execution error: HTTP request failed: error sending request for '
          'url (https://music.youtube.com/youtubei/v1/browse?alt=json&key=x)',
    ]) {
      expect(friendlyError(raw, fallback: 'x'), noInternetMessage, reason: raw);
    }
  });

  test('nothing to report falls back', () {
    expect(friendlyError(null, fallback: 'Failed'), 'Failed');
    expect(isNetworkError(null), isFalse);
  });
}
