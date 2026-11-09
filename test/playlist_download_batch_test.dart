// A playlist "Download all": when it counts as finished, and the time left
// shown in the download notification.

import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finished once every song is done or failed', () {
    final b = PlaylistDownloadBatch('Mix', {'a', 'b', 'c'});
    expect(b.finished, isFalse);
    b.done.add('a');
    b.failed.add('b');
    expect(b.finished, isFalse);
    b.done.add('c');
    expect(b.finished, isTrue);
    expect(b.settled, 3);
  });

  test('time left follows the pace of the songs done so far', () {
    final b = PlaylistDownloadBatch('Mix', {'a', 'b', 'c', 'd'});
    expect(b.eta, isNull); // nothing done yet
    b.done.add('a');
    b.lastDone = b.started.add(const Duration(seconds: 30));
    // 30 s per song, 3 songs to go.
    expect(b.eta, const Duration(seconds: 90));
  });
}
