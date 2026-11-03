// Layer 2: the "why this was suggested" line follows what was learned.

import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/recs_dataset.dart';

void main() {
  final ranker =
      RecommendationRanker(CrossPluginResolver(pluginService: PluginService()));
  final seed = tr('s', 'Seed Song', 'Seed Singer', sec: 200);
  final pick = tr('p', 'Softly', 'Karan Aujla', sec: 200);

  RecReason reasonWith(TasteModel? model) {
    final taste = UserTaste(
      languages: const {SongLanguage.hindi, SongLanguage.punjabi},
      cards: SongCardReader(songKey: ranker.songKey),
      model: model,
    );
    return ranker
        .rank(
            seed: seed,
            candidates: from(RecSource.radio, [pick]),
            taste: taste)
        .single
        .reason;
  }

  test('a language that matters to this listener becomes the reason', () {
    // Language doesn't matter to this listener: not the reason.
    final fresh = TasteModel.fresh()..weights['language'] = 0.0;
    expect(reasonWith(fresh).kind, RecReasonKind.becausePlaying);

    // Learned that language matters a lot to this listener.
    final learned = TasteModel.fresh()..weights['language'] = 0.6;
    expect(reasonWith(learned),
        const RecReason(RecReasonKind.inLanguage, 'punjabi'));
  });
}
