import 'dart:async';
import 'dart:developer';

import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/db/legacy/legacy_media_id_mapper.dart'
    show pluginYtMusicId;
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:Bloomee/src/rust/api/plugin/types.dart';

class GatherResult {
  /// Radio first, then the seed artist, the other plugin, related artist.
  final List<RecCandidate> candidates;

  /// For the next radio page, if the plugin has one.
  final String? nextRadioPage;

  const GatherResult(this.candidates, this.nextRadioPage);

  static const empty = GatherResult([], null);
}

/// Collects recommendation candidates for a seed track from the loaded
/// content-resolver plugins.
///
/// First call for a seed (≈5 plugin calls, in parallel where possible):
/// its radio, its artist's top tracks, one related artist's top tracks, and
/// radio for the same song on one other loaded plugin. Later calls
/// ([radioPage] set) fetch only the next radio page. A seed from this device
/// is first matched to a plugin track (one more call). Every call has its own
/// timeout; one that fails or times out just adds nothing.
///
/// The main radio is YouTube Music's whenever it is loaded, also for seeds
/// from JioSaavn or YouTube Video (matched by title, artist and length): it
/// is long, pages on, and varies artists, while JioSaavn's is ~15 songs of
/// mostly one composer, which then joins as the "other plugin" source.
class CandidateGatherer {
  final PluginService _plugins;
  final CrossPluginResolver _matcher;
  final Duration timeout;

  CandidateGatherer(this._plugins, this._matcher,
      {this.timeout = const Duration(seconds: 8)});

  static const _radioPlugin = pluginYtMusicId;
  static const _keepFirstPage = Duration(hours: 24);

  // Seed id -> first gather (autoplay keeps one gatherer), and the
  // radio plugin + track that later pages continue from.
  final _firstPages = <String, (DateTime, GatherResult)>{};
  final _radioAnchors = <String, (String, Track)>{};

  Future<GatherResult> gather(Track seed, {String? radioPage}) async {
    final List<String> resolvers;
    try {
      resolvers = await _loadedResolvers();
    } catch (e) {
      log('Listing resolver plugins failed: $e', name: 'CandidateGatherer');
      return GatherResult.empty;
    }
    if (resolvers.isEmpty) return GatherResult.empty;

    var anchor = seed;
    var home = tryParseMediaId(seed.id)?.pluginId;
    if (home == null || !resolvers.contains(home)) {
      // A local file, or a track from a plugin that's not loaded: find the
      // same song on a loaded one.
      final match = await _match(seed, resolvers);
      if (match == null) return GatherResult.empty;
      anchor = match.track;
      home = match.pluginId;
    }

    if (radioPage != null) {
      final (plugin, track) = _radioAnchors[seed.id] ?? (home, anchor);
      final r = await _radio(plugin, track, RecSource.radio, radioPage);
      return GatherResult(r.$1, r.$2);
    }

    final cached = _firstPages[seed.id];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < _keepFirstPage) {
      return cached.$2;
    }

    final homeRadio = _radio(home, anchor, RecSource.radio, null);
    final artistSources = _artistSources(home, anchor);
    final useYt = home != _radioPlugin && resolvers.contains(_radioPlugin);
    final yt = useYt ? await _match(anchor, [_radioPlugin]) : null;

    final GatherResult result;
    if (yt != null) {
      final ytRadio =
          await _radio(_radioPlugin, yt.track, RecSource.radio, null);
      final own = (await homeRadio).$1;
      final byArtist = await artistSources;
      _radioAnchors[seed.id] = (_radioPlugin, yt.track);
      result = GatherResult(
        [
          ...ytRadio.$1,
          ...byArtist.where((c) => c.source == RecSource.seedArtist),
          for (final c in own)
            RecCandidate(c.track, RecSource.otherPlugin, c.rank),
          ...byArtist.where((c) => c.source == RecSource.relatedArtist),
        ],
        ytRadio.$2,
      );
    } else {
      final others = resolvers.where((p) => p != home).toList()
        ..sort((a, b) =>
            (b == _radioPlugin ? 1 : 0) - (a == _radioPlugin ? 1 : 0));
      final results = await Future.wait([
        homeRadio,
        artistSources.then((c) => (c, null)),
        if (others.isNotEmpty && !useYt)
          _otherPlugin(others.first, anchor).then((c) => (c, null)),
      ]);
      final byArtist = results[1].$1;
      _radioAnchors[seed.id] = (home, anchor);
      result = GatherResult(
        [
          ...results[0].$1,
          ...byArtist.where((c) => c.source == RecSource.seedArtist),
          if (results.length > 2) ...results[2].$1,
          ...byArtist.where((c) => c.source == RecSource.relatedArtist),
        ],
        results[0].$2,
      );
    }
    if (result.candidates.isNotEmpty) {
      _firstPages[seed.id] = (DateTime.now(), result);
    }
    return result;
  }

  Future<(List<RecCandidate>, String?)> _radio(
      String plugin, Track anchor, RecSource source, String? page) async {
    final response = await _call(
        plugin,
        ContentResolverCommand.getRadioTracks(
            id: localIdOf(anchor.id) ?? anchor.id, pageToken: page));
    if (response is! PluginResponse_MoreTracks) return (<RecCandidate>[], null);
    final items = response.field0.items;
    return (
      [
        for (var i = 0; i < items.length; i++) RecCandidate(items[i], source, i)
      ],
      response.field0.nextPageToken,
    );
  }

  /// The anchor artist's top tracks, then one related artist's.
  Future<List<RecCandidate>> _artistSources(String plugin, Track anchor) async {
    if (anchor.artists.isEmpty) return const [];
    final details = await _artist(plugin, anchor.artists.first.id);
    if (details == null) return const [];
    final out = [
      for (var i = 0; i < details.topTracks.length; i++)
        RecCandidate(details.topTracks[i], RecSource.seedArtist, i),
    ];
    if (details.relatedArtists.isNotEmpty) {
      final related = await _artist(plugin, details.relatedArtists.first.id);
      final top = related?.topTracks ?? const <Track>[];
      for (var i = 0; i < top.length && i < 10; i++) {
        out.add(RecCandidate(top[i], RecSource.relatedArtist, i));
      }
    }
    return out;
  }

  Future<ArtistDetails?> _artist(String plugin, String artistId) async {
    final response = await _call(
        plugin,
        ContentResolverCommand.getArtistDetails(
            id: localIdOf(artistId) ?? artistId));
    return response is PluginResponse_ArtistDetails ? response.field0 : null;
  }

  /// Radio for the same song on [plugin], if it has a confident match.
  Future<List<RecCandidate>> _otherPlugin(String plugin, Track anchor) async {
    final match = await _match(anchor, [plugin]);
    if (match == null) return const [];
    return (await _radio(plugin, match.track, RecSource.otherPlugin, null)).$1;
  }

  Future<ScoredTrackCandidate?> _match(
      Track track, List<String> plugins) async {
    final target = TrackMatchTarget.fromTrack(track);
    try {
      final found = await _matcher.resolveTrack(
        target: target,
        pluginIds: plugins,
        limit: 1,
        minConfidence: 0.8,
        sequential: true,
        queries: ['${target.title} ${target.primaryArtist}'.trim()],
      ).timeout(timeout);
      return found.isEmpty ? null : found.first;
    } catch (e) {
      log('Matching "${track.title}" failed: $e', name: 'CandidateGatherer');
      return null;
    }
  }

  Future<PluginResponse?> _call(
      String plugin, ContentResolverCommand cmd) async {
    try {
      return await _plugins
          .execute(
              pluginId: plugin, request: PluginRequest.contentResolver(cmd))
          .timeout(timeout);
    } catch (e) {
      log('$cmd on $plugin failed: $e', name: 'CandidateGatherer');
      return null;
    }
  }

  Future<List<String>> _loadedResolvers() async {
    final available = await _plugins.getAvailablePlugins();
    final loaded = _plugins.getLoadedPlugins().toSet();
    return [
      for (final p in available)
        if (p.pluginType == PluginType.contentResolver &&
            loaded.contains(p.manifest.id))
          p.manifest.id,
    ];
  }
}
