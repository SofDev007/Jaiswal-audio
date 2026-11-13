import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/services/player/listening_time.dart';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/screens/screen/home_views/setting_views/setting_shared_widgets.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/player/related_songs_manager.dart';
import 'package:Bloomee/services/recommendations/rec_health.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:flutter/material.dart';

/// Developer page, not in Settings: open it by tapping the version on the
/// About screen 7 times. Shows how recommendations are doing on this phone
/// (RecHealth) and the languages JARX has learned; nothing here is a user
/// control (recommendations manage themselves).
class RecommendationHealthView extends StatefulWidget {
  const RecommendationHealthView({super.key});

  @override
  State<RecommendationHealthView> createState() =>
      _RecommendationHealthViewState();
}

class _RecommendationHealthViewState extends State<RecommendationHealthView> {
  Map<String, int> _health = const {};
  Set<SongLanguage>? _languages;
  Map<SongLanguage, double> _shares = const {};
  TasteModel? _model;
  ListeningStats? _listening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final health = await RecHealth.load();
    final model = await TasteModel.load();
    final listening = await ListeningTime.load();
    Set<SongLanguage>? languages;
    var shares = const <SongLanguage, double>{};
    try {
      final plugins = ServiceLocator.pluginService;
      final taste = await RelatedSongsManager.tasteFromDevice(
          RecommendationRanker(CrossPluginResolver(pluginService: plugins)));
      languages = taste.languages;
      shares = taste.languageShares;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _health = health;
      _languages = languages;
      _shares = shares;
      _model = model;
      _listening = listening;
    });
  }

  /// The [n] artists listened to longest.
  List<({String name, int ms})> _topArtists(int n) {
    final all = _listening?.artists.values.toList() ?? [];
    all.sort((x, y) => y.ms.compareTo(x.ms));
    return all.take(n).toList();
  }

  String _pct(int part, int whole) =>
      whole == 0 ? '–' : '${(100 * part / whole).round()}%';

  @override
  Widget build(BuildContext context) {
    final h = _health;
    final refills = h[RecHealth.refills] ?? 0;
    final gathers = h[RecHealth.gathers] ?? 0;
    final starts = h[RecHealth.recStarts] ?? 0;
    final langs = _languages;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Default_Theme.themeColor,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Default_Theme.primaryColor1),
        title: const Text('Recommendation health',
            style: TextStyle(
                color: Default_Theme.primaryColor1,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          const SettingSectionHeader(label: 'Learned from listening'),
          SettingCard(children: [
            _Row(
                'Languages',
                langs == null
                    ? '…'
                    : langs.isEmpty
                        ? 'not enough plays yet'
                        : langs.map((l) => l.name).join(', ')),
            // Every language heard, so a missing one can be checked.
            for (final e in (_shares.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value))))
              _Row('  ${e.key.name}', '${(e.value * 100).round()}%'),
          ]),
          const SizedBox(height: 28),
          const SettingSectionHeader(label: 'Listening time (for Your corner)'),
          SettingCard(children: [
            _Row(
                'Total',
                _listening == null
                    ? '…'
                    : '${_listening!.totalMs ~/ 60000} min since '
                        '${_listening!.since.day}/${_listening!.since.month}/${_listening!.since.year}'),
            for (final a in _topArtists(3))
              _Row('  ${a.name}', '${a.ms ~/ 60000} min'),
            _Row('Songs counted', '${_listening?.songs.length ?? 0}'),
            for (final t in _listening?.topSongs(3) ?? const <SongStat>[])
              _Row('  ${t.title}', '${t.plays}× · ${t.ms ~/ 60000} min'),
          ]),
          const SizedBox(height: 28),
          const SettingSectionHeader(label: 'Learned weights (Layer 2)'),
          SettingCard(children: [
            _Row('Learned from', '${_model?.updates ?? 0} suggestions'),
            for (final k in TasteModel.prior.keys)
              _Row(
                  '  $k',
                  _model == null
                      ? '…'
                      : '${_model!.weight(k).toStringAsFixed(3)}'
                          ' (${(_model!.weight(k) - TasteModel.prior[k]!) >= 0 ? '+' : ''}'
                          '${(_model!.weight(k) - TasteModel.prior[k]!).toStringAsFixed(3)})'),
          ]),
          const SizedBox(height: 28),
          const SettingSectionHeader(label: 'Autoplay'),
          SettingCard(children: [
            _Row('Refills', '$refills'),
            _Row('Filled from own songs',
                _pct(h[RecHealth.libraryRefills] ?? 0, refills)),
            _Row('Ran dry', _pct(h[RecHealth.emptyRefills] ?? 0, refills)),
            _Row(
                'Time to find suggestions',
                gathers == 0
                    ? '–'
                    : '${((h[RecHealth.gatherMs] ?? 0) / gathers / 1000).toStringAsFixed(1)} s'),
            _Row('Recommended songs played', '$starts'),
            _Row('…skipped in the first 30 s',
                _pct(h[RecHealth.recEarlySkips] ?? 0, starts)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                await RecHealth.reset();
                await _load();
              },
              child: const Text('Reset counters',
                  style: TextStyle(color: Default_Theme.accentColor2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Default_Theme.primaryColor1, fontSize: 15))),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: Default_Theme.primaryColor2.withValues(alpha: 0.8),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
