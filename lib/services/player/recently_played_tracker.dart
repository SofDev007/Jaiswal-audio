import 'dart:async';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'dart:developer';

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/history_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/dao/track_signal_dao.dart';

/// Tracks continuous playback of the current track and pushes it to the
/// playback history DB and the recommendation signals only once it has played
/// for more than [_thresholdSeconds] (20). Shorter plays don't count, however
/// short the song.
class RecentlyPlayedTracker {
  final PlayerEngine _engine;
  final Track? Function() _getCurrentTrack;

  int _thresholdSeconds;
  StreamSubscription<EngineState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  // Tracking state
  String? _trackingMediaId;
  int? _startPositionMs;
  bool _recordedForCurrent = false;
  int? _lastPositionMs;
  int? _lastPositionTimestampMs;

  RecentlyPlayedTracker(
    this._engine,
    this._getCurrentTrack, {
    int thresholdSeconds = 20,
  }) : _thresholdSeconds = thresholdSeconds {
    _stateSub = _engine.stateStream.listen(_onEngineState);
    _positionSub = _engine.positionStream.listen(_onPosition);
  }

  void _onEngineState(EngineState state) {
    final isPlaying = _engine.playing;
    final track = _getCurrentTrack();
    final mediaId = track?.id;

    if (isPlaying && state == EngineState.ready) {
      if (track == null) return;
      if (_trackingMediaId != mediaId) {
        _trackingMediaId = mediaId;
        _recordedForCurrent = false;
        _startPositionMs = _engine.position.inMilliseconds;
        _lastPositionMs = _startPositionMs;
        _lastPositionTimestampMs = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (state == EngineState.idle ||
        state == EngineState.completed ||
        state == EngineState.error) {
      _trackingMediaId = null;
      _startPositionMs = null;
      _lastPositionMs = null;
      _lastPositionTimestampMs = null;
    }
  }

  Future<void> _onPosition(Duration position) async {
    if (_trackingMediaId == null || _recordedForCurrent) return;

    final track = _getCurrentTrack();
    if (track == null || track.id != _trackingMediaId) {
      _trackingMediaId = null;
      _startPositionMs = null;
      return;
    }

    final currMs = position.inMilliseconds;
    final startMs = _startPositionMs ?? currMs;
    if (currMs < startMs) {
      _startPositionMs = currMs;
      _lastPositionMs = currMs;
      _lastPositionTimestampMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }

    final nowTs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPositionMs != null && _lastPositionTimestampMs != null) {
      final posDelta = currMs - _lastPositionMs!;
      final timeDelta = nowTs - _lastPositionTimestampMs!;
      if (posDelta > timeDelta + 1000) {
        _startPositionMs = currMs;
        _lastPositionMs = currMs;
        _lastPositionTimestampMs = nowTs;
        return;
      }
    }
    _lastPositionMs = currMs;
    _lastPositionTimestampMs = nowTs;

    final elapsedMs = currMs - startMs;

    if (elapsedMs > _thresholdSeconds * 1000) {
      _recordedForCurrent = true;
      try {
        final trackDao = TrackDAO(DBProvider.db);
        final historyDao = HistoryDAO(DBProvider.db, trackDao);
        await historyDao.recordPlay(track);
        await TrackSignalDAO(DBProvider.db).recordPlay(track);
        // Kept past 20 s: a good suggestion, if it was one; and its moods
        // count for this time of day.
        await TasteModel.played(track.id, good: true);
        await TasteModel.notePlay(track);
        log('Tracked play for ${track.id}', name: 'RecentlyPlayedTracker');
      } catch (e) {
        log('Failed to record play: $e', name: 'RecentlyPlayedTracker');
      }
    }
  }

  void setThresholdSeconds(int seconds) {
    if (seconds <= 0) return;
    _thresholdSeconds = seconds;
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _positionSub?.cancel();
  }
}
