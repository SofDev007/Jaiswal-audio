import 'dart:convert';

import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:rxdart/rxdart.dart';

/// Songs the user never wants suggested (the minus button on suggestions).
///
/// Stored by song key (simplified title + main artist), so the same song
/// from another source or upload stays out too. Only suggestions skip these
/// songs: playing one yourself (search, playlist, album) still works.
class SuggestionBlocklist {
  SuggestionBlocklist._();

  /// The blocked song keys; empty until [load] has run.
  static final keys = BehaviorSubject<Set<String>>.seeded(const {});
  static Future<Set<String>>? _loading;

  static final _ranker = RecommendationRanker(
      CrossPluginResolver(pluginService: ServiceLocator.pluginService));

  static String keyOf(Track t) => _ranker.songKey(t);

  static Future<Set<String>> load() => _loading ??= () async {
        final raw = await SettingsDAO(DBProvider.db)
            .getSettingStr(SettingKeys.blockedSuggestions);
        keys.add(decode(raw));
        return keys.value;
      }();

  static Future<void> block(Track t) async =>
      _save({...await load(), keyOf(t)});

  static Future<void> unblock(Track t) async =>
      _save({...await load()}..remove(keyOf(t)));

  static Future<void> _save(Set<String> next) async {
    keys.add(next);
    await SettingsDAO(DBProvider.db)
        .putSettingStr(SettingKeys.blockedSuggestions, jsonEncode([...next]));
  }

  /// The stored JSON list, or nothing when it is missing or unreadable.
  static Set<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return {...(jsonDecode(raw) as List).cast<String>()};
    } catch (_) {
      return const {};
    }
  }
}
