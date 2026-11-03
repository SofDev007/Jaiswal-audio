import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/db/legacy/legacy_media_id_mapper.dart'
    show pluginYtMusicId, pluginYtVideoId;
import 'package:Bloomee/services/meta_resolver/smart_track_replacement_service.dart';

/// The same song from another source, for when its own source can't stream
/// or download it (YouTube now blocks some songs, e.g. "Mauja Hi Mauja").
class FallbackPick {
  final Track track;
  final String pluginName;

  /// Version words the original has ("reprise", "unplugged", ...).
  final Set<String> wanted;

  /// The pick has all of [wanted]; when false it is another recording.
  final bool sameVersion;

  const FallbackPick(
      this.track, this.pluginName, this.wanted, this.sameVersion);
}

/// Picks the best other-source copy of [track], or null.
///
/// Never the same YouTube video under the other YouTube plugin (it breaks
/// the same way). Ranked: shares an artist (keeps out random uploads that
/// only copy the title), then same version words, then not YouTube.
Future<FallbackPick?> pickFallback(
    SmartTrackReplacementService service, Track track) async {
  const youtube = {pluginYtMusicId, pluginYtVideoId};
  final video = localIdOf(track.id);
  final wanted = versionWords(track.title);
  final artists = {for (final a in track.artists) a.name.toLowerCase()};
  bool sharesArtist(Track t) =>
      t.artists.any((a) => artists.contains(a.name.toLowerCase()));
  bool sameVersion(Track t) => versionWords(t.title).containsAll(wanted);
  int rank(SmartTrackReplacementCandidate c) =>
      (sharesArtist(c.track) ? 0 : 4) +
      (sameVersion(c.track) ? 0 : 2) +
      (youtube.contains(c.pluginId) ? 1 : 0);

  final usable = [
    for (final c in await service.searchCandidates(track))
      if (c.confidence >= 0.45 && localIdOf(c.track.id) != video) c,
  ]..sort((a, b) => rank(a).compareTo(rank(b)));
  if (usable.isEmpty) return null;
  final c = usable.first;
  return FallbackPick(c.track, c.pluginName, wanted, sameVersion(c.track));
}

const _versionTags = {
  'reprise',
  'unplugged',
  'acoustic',
  'female',
  'male',
  'duet',
  'sad',
  'lofi',
  'remix',
  'live',
  'recreated',
  'slowed',
  'reverb',
  'instrumental',
};

/// The version words in a title: "Tum Jo Aaye (Reprise)" -> {reprise}.
Set<String> versionWords(String title) => title
    .toLowerCase()
    .split(RegExp(r'[^a-z]+'))
    .where(_versionTags.contains)
    .toSet();
