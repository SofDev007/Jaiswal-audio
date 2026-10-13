import 'dart:async';
import 'dart:developer';

import 'package:Bloomee/plugins/utils/media_id.dart';
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
class CandidateGatherer {
  final PluginService _plugins;
  final CrossPluginResolver _matcher;
  final Duration timeout;

  const CandidateGatherer(this._plugins, this._matcher,
      {this.timeout = const Duration(seconds: 8)});

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

    final radio = _radio(home, anchor, RecSource.radio, radioPage);
    if (radioPage != null) {
      final r = await radio;
      return GatherResult(r.$1, r.$2);
    }

    final others = resolvers.where((p) => p != home).toList();
    final results = await Future.wait([
      radio,
      _artistSources(home, anchor).then((c) => (c, null)),
      if (others.isNotEmpty)
        _otherPlugin(others.first, anchor).then((c) => (c, null)),
    ]);
    final byArtist = results[1].$1;
    return GatherResult(
      [
        ...results[0].$1,
        ...byArtist.where((c) => c.source == RecSource.seedArtist),
        if (results.length > 2) ...results[2].$1,
        ...byArtist.where((c) => c.source == RecSource.relatedArtist),
      ],
      results[0].$2,
    );
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
