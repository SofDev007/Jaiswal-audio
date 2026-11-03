import 'dart:developer';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/db/dao/history_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/dao/track_signal_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/global_db.dart' show PlaylistTypeDB;
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/candidate_gatherer.dart';
import 'package:Bloomee/services/recommendations/rec_health.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/services/recommendations/suggestion_blocklist.dart';
import 'package:rxdart/rxdart.dart';

typedef TasteLoader = Future<UserTaste> Function(RecommendationRanker ranker);
typedef HealthCounter = void Function(String counter, [int by]);

/// Tracks queued per refill.
const int kRecommendationBatch = 5;

/// Autoplay: when the queue is about to run out, queues a small ranked batch
/// of recommendations for the last track the user chose.
class RelatedSongsManager {
  /// The batch most recently queued.
  final BehaviorSubject<List<Track>> relatedSongs =
      BehaviorSubject<List<Track>>.seeded([]);

  /// Why each auto-queued track was suggested, by track ID.
  final BehaviorSubject<Map<String, RecReason>> reasons =
      BehaviorSubject<Map<String, RecReason>>.seeded({});

  final CandidateGatherer _gatherer;
  final RecommendationRanker _ranker;
  final TasteLoader _loadTaste;
  final Future<bool> Function() _autoPlayEnabled;
  final HealthCounter _health;

  Track? _seed;
  bool _gathered = false;
  final List<RecCandidate> _pool = [];
  String? _nextRadioPage;
  final Set<String> _autoAdded = {};
  bool _busy = false;

  Function(List<Track> items, {bool atLast})? onAddQueueItems;

  RelatedSongsManager(
    PluginService plugins, {
    CandidateGatherer? gatherer,
    RecommendationRanker? ranker,
    TasteLoader? loadTaste,
    Future<bool> Function()? autoPlayEnabled,
    HealthCounter? health,
  })  : _health = health ?? RecHealth.add,
        _gatherer = gatherer ??
            CandidateGatherer(
                plugins, CrossPluginResolver(pluginService: plugins)),
        _ranker = ranker ??
            RecommendationRanker(CrossPluginResolver(pluginService: plugins)),
        _loadTaste = loadTaste ?? tasteFromDevice,
        _autoPlayEnabled = autoPlayEnabled ?? _autoPlaySetting;

  static Future<bool> _autoPlaySetting() async =>
      await SettingsDAO(DBProvider.db).getSettingBool(SettingKeys.autoPlay) !=
      false;

  static Future<UserTaste> tasteFromDevice(RecommendationRanker ranker) async {
    final trackDao = TrackDAO(DBProvider.db);
    final results = await Future.wait([
      TrackSignalDAO(DBProvider.db).getAll(),
      PlaylistDAO(DBProvider.db, trackDao)
          .loadPlaylist(PlaylistDAO.likedPlaylist)
          .then((p) => p.tracks),
      HistoryDAO(DBProvider.db, trackDao).getHistory(limit: 200),
      SuggestionBlocklist.load(),
      _userPlaylists(trackDao),
    ]);
    return ranker.buildTaste(
      signals: results[0] as List<TrackSignal>,
      liked: results[1] as List<Track>,
      history: results[2] as List<Track>,
      blocked: results[3] as Set<String>,
      playlists: results[4] as Map<String, List<Track>>,
      model: await TasteModel.load(),
    );
  }

  static (DateTime, Map<String, List<Track>>)? _playlistsCache;

  /// The user's own playlists by name (not Liked, Downloads or Local music),
  /// re-read at most every 10 minutes: refills ask for this every time.
  static Future<Map<String, List<Track>>> _userPlaylists(
      TrackDAO trackDao) async {
    final cached = _playlistsCache;
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      return cached.$2;
    }
    final dao = PlaylistDAO(DBProvider.db, trackDao);
    const skip = {
      PlaylistDAO.likedPlaylist,
      SettingKeys.downloadPlaylist,
      SettingKeys.localMusicPlaylist,
      SettingKeys.recentlyPlayedPlaylist,
    };
    final out = <String, List<Track>>{};
    for (final p in await dao.getPlaylistsByType(PlaylistTypeDB.userPlaylist)) {
      if (skip.contains(p.name)) continue;
      out[p.name] = (await dao.loadPlaylist(p.name)).tracks;
    }
    _playlistsCache = (DateTime.now(), out);
    return out;
  }

  Future<void> checkForRelatedSongs({
    required Track currentMedia,
    required List<Track> queue,
    required int currentPlayingIdx,
    required LoopMode loopMode,
  }) async {
    final left = queue.length - currentPlayingIdx;
    // Gather while a few songs are still left, so the pool is ready (plugin
    // calls can take many seconds on mobile data); queue at the last one.
    final shouldGather =
        queue.isNotEmpty && left <= 4 && loopMode != LoopMode.all;
    final shouldQueueMore = shouldGather && left < 2;
    if (_busy || !shouldGather || !await _autoPlayEnabled()) return;

    _busy = true;
    try {
      // The refill at the last song uses the last track the user chose, so
      // gather early for that one, not for the one playing now.
      final seed = _seedFor(queue, queue.length - 1) ?? currentMedia;
      if (seed.id != _seed?.id) {
        _seed = seed;
        _gathered = false;
        _pool.clear();
        _nextRadioPage = null;
      }

      UserTaste taste;
      try {
        taste = await _loadTaste(_ranker);
      } catch (e) {
        log('Loading listening signals failed: $e', name: 'RelatedSongs');
        taste = UserTaste.empty;
      }

      if (!_gathered) {
        _gathered = true;
        final started = DateTime.now();
        _addToPool(await _gatherer.gather(seed));
        _health(RecHealth.gathers);
        _health(RecHealth.gatherMs,
            DateTime.now().difference(started).inMilliseconds);
      }
      if (!shouldQueueMore) return;
      _health(RecHealth.refills);
      var batch = _rank(seed, queue, taste);
      // Short of a full batch: up to two more radio pages.
      for (var i = 0;
          i < 2 &&
              batch.length < kRecommendationBatch &&
              _nextRadioPage != null;
          i++) {
        _addToPool(await _gatherer.gather(seed, radioPage: _nextRadioPage));
        batch = _rank(seed, queue, taste);
      }
      if (batch.isEmpty && taste.library.isNotEmpty) {
        // Every source failed or was used up: the user's own songs.
        log('No plugin candidates for "${seed.title}"; using the library',
            name: 'RelatedSongs');
        _pool.addAll([
          for (var i = 0; i < taste.library.length; i++)
            RecCandidate(taste.library[i], RecSource.library, i),
        ]);
        batch = _rank(seed, queue, taste);
        if (batch.isNotEmpty) _health(RecHealth.libraryRefills);
      }
      if (batch.isEmpty) {
        _health(RecHealth.emptyRefills);
        return;
      }

      final tracks = [for (final r in batch) r.track];
      final ids = {for (final t in tracks) t.id};
      _pool.removeWhere((c) => ids.contains(c.track.id));
      _autoAdded.addAll(ids);
      reasons.add({
        ...reasons.value,
        for (final r in batch) r.track.id: r.reason,
      });
      for (final r in batch) {
        TasteModel.remember(r.track.id, r.features);
      }
      relatedSongs.add(tracks);
      log('Queued ${tracks.length} recommendations for "${seed.title}"',
          name: 'RelatedSongs');
      onAddQueueItems?.call(tracks, atLast: true);
    } catch (e) {
      log('Recommendations failed: $e', name: 'RelatedSongs');
    } finally {
      _busy = false;
    }
  }

  /// The last track at or before [index] the user chose (not auto-queued),
  /// so a run of recommendations doesn't drift away from it.
  Track? _seedFor(List<Track> queue, int index) {
    for (var i = index.clamp(0, queue.length - 1); i >= 0; i--) {
      if (!_autoAdded.contains(queue[i].id)) return queue[i];
    }
    return null;
  }

  void _addToPool(GatherResult r) {
    _pool.addAll(r.candidates);
    _nextRadioPage = r.nextRadioPage;
  }

  List<Recommendation> _rank(Track seed, List<Track> queue, UserTaste taste) {
    final last = queue.isEmpty || queue.last.artists.isEmpty
        ? null
        : artistKeyOf(queue.last.artists.first.name);
    return _ranker.rank(
      seed: seed,
      candidates: _pool,
      taste: taste,
      excludeSongKeys: {for (final t in queue) _ranker.songKey(t)},
      previousArtistKey: last,
      take: kRecommendationBatch,
    );
  }

  void clearRelatedSongs() {
    relatedSongs.add([]);
    reasons.add({});
    _autoAdded.clear();
    _seed = null;
    _gathered = false;
    _pool.clear();
    _nextRadioPage = null;
  }

  void dispose() {
    relatedSongs.close();
    reasons.close();
  }
}
