import 'package:Bloomee/core/models/track_signal.dart' show artistKeyOf;
import 'package:Bloomee/services/first_run.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artists offered follow the picked languages', () {
    final punjabi = artistsFor({SongLanguage.punjabi});
    expect(punjabi, contains('AP Dhillon'));
    expect(punjabi, isNot(contains('Arijit Singh')));
    final all = artistsFor({});
    expect(all, containsAll(['AP Dhillon', 'Arijit Singh', 'Ed Sheeran']));
    expect(all.length, all.toSet().length, reason: 'each artist once');
  });

  test('picks survive a save and load', () {
    const p = FirstRunPicks(
        {SongLanguage.hindi, SongLanguage.punjabi}, ['Arijit Singh', 'Shubh']);
    final back = FirstRunPicks.fromJson(p.toJson());
    expect(back.languages, p.languages);
    expect(back.artists, p.artists);
  });

  test('a new user starts from their picks', () {
    final ranker =
        RecommendationRanker(CrossPluginResolver(pluginService: PluginService()));
    final taste = ranker.buildTaste(
      signals: const [],
      liked: const [],
      history: const [],
      startLanguages: {SongLanguage.punjabi},
      startArtists: ['AP Dhillon'],
    );
    expect(taste.languages, {SongLanguage.punjabi});
    expect(taste.artistAffinity[artistKeyOf('AP Dhillon')], greaterThan(0.3));

    final nothing = ranker.buildTaste(
        signals: const [], liked: const [], history: const []);
    expect(nothing.languages, isEmpty);
    expect(nothing.artistAffinity, isEmpty);
  });
}
