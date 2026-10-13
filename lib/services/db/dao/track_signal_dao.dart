import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:isar_community/isar.dart';

/// Per-track listening signals (plays, completions, early skips) for
/// on-device recommendations. Nothing here leaves the device.
class TrackSignalDAO {
  final Future<Isar> _db;

  const TrackSignalDAO(this._db);

  Future<void> recordPlay(Track track) => _update(
      track,
      (s) => s
        ..plays += 1
        ..lastPlayedAt = DateTime.now());

  Future<void> recordCompletion(Track track) =>
      _update(track, (s) => s.completions += 1);

  Future<void> recordEarlySkip(Track track) =>
      _update(track, (s) => s.earlySkips += 1);

  /// All signals, most recently played first.
  Future<List<TrackSignal>> getAll() async {
    final isar = await _db;
    final rows =
        await isar.trackSignalDBs.where().sortByLastPlayedAtDesc().findAll();
    return [
      for (final r in rows)
        TrackSignal(
          mediaId: r.mediaId,
          artistKey: r.artistKey,
          artistName: r.artistName,
          plays: r.plays,
          completions: r.completions,
          earlySkips: r.earlySkips,
          lastPlayedAt: r.lastPlayedAt,
        ),
    ];
  }

  Future<void> clear() async {
    final isar = await _db;
    await isar.writeTxn(() => isar.trackSignalDBs.clear());
  }

  Future<void> _update(Track track, void Function(TrackSignalDB) change) async {
    final isar = await _db;
    final artist = track.artists.isEmpty ? '' : track.artists.first.name.trim();
    await isar.writeTxn(() async {
      final row = await isar.trackSignalDBs
              .filter()
              .mediaIdEqualTo(track.id)
              .findFirst() ??
          TrackSignalDB(
            mediaId: track.id,
            artistKey: artistKeyOf(artist),
            artistName: artist,
          );
      change(row);
      await isar.trackSignalDBs.put(row);
    });
  }
}
