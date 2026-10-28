// Home: the three layouts the user can pick from (see HomeLayout) and the
// rows they are built from. A "For you": greeting, Continue listening and
// For you cards. B "Mixes": mood shortcuts, a playlist grid and Today's mix.
// C "Pulse": Jump back in, Up next for you and Your playlists.

import 'dart:async';
import 'dart:convert';

import 'package:Bloomee/blocs/explore/cubit/explore_cubits.dart';
import 'package:Bloomee/blocs/library/cubit/library_items_cubit.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/constants/route_paths.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/screens/screen/home_views/recents_view.dart';
import 'package:Bloomee/screens/screen/home_views/setting_views/about.dart';
import 'package:Bloomee/screens/screen/library_screen.dart'
    show openLibraryItem;
import 'package:Bloomee/screens/widgets/live_visualizer.dart';
import 'package:Bloomee/screens/widgets/more_bottom_sheet.dart';
import 'package:Bloomee/screens/widgets/never_suggest_button.dart';
import 'package:Bloomee/screens/widgets/up_next_panel.dart' show recReasonText;
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/player/related_songs_manager.dart';
import 'package:Bloomee/services/recommendations/candidate_gatherer.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/services/recommendations/suggestion_blocklist.dart';
import 'package:Bloomee/utils/load_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The Home layouts, stored by name in [SettingKeys.homeLayout].
enum HomeLayout { forYou, mixes, pulse }

/// The stored layout, or Pulse when none has been picked yet.
HomeLayout homeLayoutOf(String name) =>
    HomeLayout.values.asNameMap()[name] ?? HomeLayout.pulse;

// Card surface and hairline colours from the mock-ups.
const _surface = Color(0xFF17171B);
const _line = Color(0xFF2A2A31);
final _muted = Default_Theme.primaryColor1.withValues(alpha: 0.6);

String _artistNames(Track t) => t.artists.map((a) => a.name).join(', ');

void _play(BuildContext context, List<Track> tracks, String title, int idx) =>
    context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
          Playlist(tracks: tracks, title: title),
          idx: idx,
          doPlay: true,
        );

/// The rows above the plugin's Home sections for [layout]. [homeReady]
/// tells For you that the sections have loaded (see [ForYouRow]).
class HomeTop extends StatelessWidget {
  const HomeTop({super.key, required this.layout, required this.homeReady});
  final HomeLayout layout;
  final bool homeReady;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget forYou(Widget Function(List<ForYouPick> picks) builder) =>
        ForYouRow(homeReady: homeReady, builder: builder);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: switch (layout) {
        HomeLayout.forYou => [
            const ContinueListeningRow(),
            forYou((picks) => _TrackRow(
                  title: l10n.homeForYou,
                  hint: l10n.homeForYouHint,
                  tracks: [for (final (t, _) in picks) t],
                  captions: [
                    for (final (_, r) in picks) recReasonText(l10n, r)
                  ],
                  playlistTitle: l10n.homeForYou,
                )),
          ],
        HomeLayout.mixes => [
            const _MoodChips(),
            const _ShortcutGrid(),
            forYou((picks) => _TodaysMixCard(picks: picks)),
          ],
        HomeLayout.pulse => [
            const JumpBackInCard(),
            forYou((picks) => _UpNextList(picks: picks)),
            const YourPlaylistsRow(),
          ],
      },
    );
  }
}

/// Greeting for the hour of the day.
String homeGreeting(AppLocalizations l10n, int hour) => hour < 5
    ? l10n.homeGreetingEvening
    : hour < 12
        ? l10n.homeGreetingMorning
        : hour < 17
            ? l10n.homeGreetingAfternoon
            : l10n.homeGreetingEvening;

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const About())),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/icons/jarx/icon_android.png',
            width: 34, height: 34),
      ),
    );
  }
}

/// J1 logo (opens About) and the greeting: the For you layout's app bar.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        const _Logo(),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  homeGreeting(l10n, DateTime.now().hour),
                  maxLines: 1,
                  style: Default_Theme.secondoryTextStyleMedium.merge(
                      const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Default_Theme.primaryColor1)),
                ),
              ),
              Text(
                l10n.homeGreetingSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Default_Theme.secondoryTextStyle
                    .merge(TextStyle(fontSize: 12, color: _muted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// J1 logo (opens About) and the JARX wordmark: the Mixes and Pulse app bar.
class HomeTitle extends StatelessWidget {
  const HomeTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Logo(),
        const SizedBox(width: 10),
        Text(
          'JARX',
          style: Default_Theme.secondoryTextStyleMedium.merge(const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: Default_Theme.primaryColor1)),
        ),
      ],
    );
  }
}

// ── A: For you ────────────────────────────────────────────────────────────

/// Recently played tracks as a row of cards; "See all" opens the history.
class ContinueListeningRow extends StatelessWidget {
  const ContinueListeningRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<RecentlyCubit, RecentlyCubitState>(
      builder: (context, state) {
        if (state.tracks.isEmpty) return const SizedBox.shrink();
        return _TrackRow(
          title: l10n.homeContinueListening,
          tracks: state.tracks.take(12).toList(),
          playlistTitle: 'Recently',
          onSeeAll: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HistoryView())),
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.title,
    required this.tracks,
    required this.playlistTitle,
    this.hint,
    this.captions,
    this.onSeeAll,
  });

  final String title;
  final String? hint;
  final List<Track> tracks;
  final List<String>? captions;
  final String playlistTitle;
  final VoidCallback? onSeeAll;

  static const _cardSize = 132.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
                title: title,
                hint: hint,
                action: onSeeAll == null ? null : l10n.homeSeeAll,
                onAction: onSeeAll),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _cardSize + (captions == null ? 48 : 90),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final t = tracks[i];
                return GestureDetector(
                  onTap: () => _play(context, tracks, playlistTitle, i),
                  onLongPress: () =>
                      showMoreBottomSheet(context, t, showSinglePlay: true),
                  child: SizedBox(
                    width: _cardSize,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: LoadImageCached(
                                imageUrl:
                                    t.thumbnail.urlHigh ?? t.thumbnail.url,
                                fallbackUrl: t.thumbnail.url,
                                width: _cardSize,
                                height: _cardSize,
                              ),
                            ),
                            // Suggestions only: never suggest this one again.
                            if (captions != null)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                  child: NeverSuggestButton(track: t),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Default_Theme.secondoryTextStyleMedium.merge(
                                const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Default_Theme.primaryColor1))),
                        Text(_artistNames(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Default_Theme.secondoryTextStyle.merge(
                                TextStyle(fontSize: 11.5, color: _muted))),
                        if (captions != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: _ReasonChip(captions![i], maxLines: 2),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── B: Mixes ──────────────────────────────────────────────────────────────

/// Mood shortcuts; each opens Search for that mood.
class _MoodChips extends StatelessWidget {
  const _MoodChips();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Labels follow the app language; the queries stay in English, which
    // the music sources match best.
    final moods = [
      (l10n.homeMoodChill, 'chill songs'),
      (l10n.homeMoodFocus, 'focus music'),
      (l10n.homeMoodRomance, 'romantic songs'),
      (l10n.homeMoodWorkout, 'workout songs'),
      (l10n.homeMoodParty, 'party songs'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        itemCount: moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => context.pushNamed(RoutePaths.searchScreen,
              queryParameters: {'query': moods[i].$2}),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: Text(moods[i].$1,
                style: Default_Theme.secondoryTextStyle.merge(const TextStyle(
                    fontSize: 12.5, color: Default_Theme.primaryColor1))),
          ),
        ),
      ),
    );
  }
}

/// Up to six library playlists (the last slot is Recently played) as a
/// two-column grid of tiles.
class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid();

  @override
  Widget build(BuildContext context) {
    return _LibraryShortcuts(
      maxPlaylists: 5,
      builder: (items) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: _tile(items[i])),
                    const SizedBox(width: 8),
                    Expanded(
                        child: i + 1 < items.length
                            ? _tile(items[i + 1])
                            : const SizedBox.shrink()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(_Shortcut s) {
    return GestureDetector(
      onTap: s.onTap,
      child: Container(
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            LoadImageCached(imageUrl: s.image, width: 56, height: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Default_Theme.secondoryTextStyleMedium.merge(
                      const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                          color: Default_Theme.primaryColor1))),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// The For you picks as one mix: the first titles, and a button that plays
/// them all.
class _TodaysMixCard extends StatelessWidget {
  const _TodaysMixCard({required this.picks});
  final List<ForYouPick> picks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tracks = [for (final (t, _) in picks) t];
    final shown = tracks.take(3).map((t) => t.title).join(', ');
    final summary = tracks.length > 3
        ? l10n.homeMixSummary(shown, tracks.length - 3)
        : shown;
    void playAll() => _play(context, tracks, l10n.homeTodaysMix, 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: GestureDetector(
        onTap: playAll,
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1B2240),
                Color(0xFF3B1F5C),
                Default_Theme.accentColor2
              ],
              stops: [0, 0.55, 1.3],
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.homeTodaysMix.toUpperCase(),
                    style: Default_Theme.secondoryTextStyle.merge(TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: Colors.white.withValues(alpha: 0.75))),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.homeForYou,
                    style: Default_Theme.secondoryTextStyleMedium.merge(
                        const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(right: 60),
                    child: Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Default_Theme.secondoryTextStyle.merge(TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8))),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: playAll,
                  child: const _RoundPlayButton(size: 46, playing: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── C: Pulse ──────────────────────────────────────────────────────────────

/// The most recently played track as a large card. Its button resumes the
/// track when it is still the current one, otherwise plays the history
/// from it.
class JumpBackInCard extends StatelessWidget {
  const JumpBackInCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<RecentlyCubit, RecentlyCubitState>(
      builder: (context, state) {
        if (state.tracks.isEmpty) return const SizedBox.shrink();
        final recent = state.tracks.take(12).toList();
        final t = recent.first;
        final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
        void play() {
          if (player.currentMedia.id == t.id) {
            player.engine.playing ? player.pause() : player.play();
            return;
          }
          _play(context, recent, 'Recently', 0);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: GestureDetector(
            onTap: play,
            onLongPress: () =>
                showMoreBottomSheet(context, t, showSinglePlay: true),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _line),
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.3,
                    stops: const [0, 0.6],
                    colors: [
                      Default_Theme.accentColor2.withValues(alpha: 0.45),
                      Default_Theme.accentColor2.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.homeJumpBackIn.toUpperCase(),
                          style: Default_Theme.secondoryTextStyle.merge(
                              TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                  color: _muted)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: LoadImageCached(
                                imageUrl:
                                    t.thumbnail.urlHigh ?? t.thumbnail.url,
                                fallbackUrl: t.thumbnail.url,
                                width: 92,
                                height: 92,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: LivePulseVisualizer(
                                    trackId: t.id,
                                    fallback: _LivePulse(trackId: t.id)),
                              ),
                            ),
                            const SizedBox(width: 24),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(right: 80),
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Default_Theme.secondoryTextStyleMedium.merge(
                                const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Default_Theme.primaryColor1)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 80),
                          child: Text(
                            _artistNames(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Default_Theme.secondoryTextStyle.merge(
                                TextStyle(fontSize: 12.5, color: _muted)),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: play,
                        child: StreamBuilder<bool>(
                          stream: player.engine.playingStream,
                          builder: (context, snap) => _RoundPlayButton(
                            size: 62,
                            glow: true,
                            playing: (snap.data ?? false) &&
                                player.currentMedia.id == t.id,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The heartbeat line from the J1 logo, drawn across the Pulse card.
class _PulsePainter extends CustomPainter {
  const _PulsePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Same shape as the mock-up's 160 x 40 SVG path, stretched to fit.
    final sx = size.width / 160, sy = size.height / 40;
    final path = Path()
      ..moveTo(0, 22 * sy)
      ..lineTo(40 * sx, 22 * sy)
      ..lineTo(50 * sx, 6 * sy)
      ..lineTo(62 * sx, 36 * sy)
      ..lineTo(72 * sx, 22 * sy)
      ..lineTo(160 * sx, 22 * sy);
    canvas.drawPath(
      path,
      Paint()
        ..color = Default_Theme.accentColor2.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) => false;
}

/// The Pulse card's heartbeat line. Still unless [trackId] is playing; then
/// a wave driven by the music's loudness scrolls right to left and every
/// beat lifts a taller spike.
class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.trackId});

  final String trackId;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  // Tuning knobs, set by eye on the test phone.
  static const _sampleEvery = Duration(milliseconds: 33);
  static const _floorDb = -50.0; // quieter than this draws flat
  static const _lagSamples =
      6; // ~200 ms: mpv filters audio ahead of the speaker
  static const _points = 40; // spikes across the card

  late final _player = context.read<BloomeePlayerCubit>().bloomeePlayer;
  late final Ticker _ticker = createTicker(_tick);
  late final StreamSubscription<bool> _playingSub;
  final _wave = _Wave();
  Duration _last = Duration.zero;
  bool _polling = false;
  double _avg = 0;

  @override
  void initState() {
    super.initState();
    _playingSub = _player.engine.playingStream.listen((playing) {
      if (playing && !_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      } else if (!playing && _ticker.isActive) {
        _ticker.stop();
        _wave.reset();
      }
    });
  }

  Future<void> _tick(Duration elapsed) async {
    if (_polling || elapsed - _last < _sampleEvery) return;
    if (_player.currentMedia.id != widget.trackId) {
      _wave.reset();
      return;
    }
    _last = elapsed;
    _polling = true;
    final db = await _player.engine.audioLevelDb();
    _polling = false;
    if (!mounted || !_ticker.isActive) return;
    // No loudness reading (see PlayerEngine.audioLevelDb): a steady
    // "lub-dub" heartbeat at 75 bpm instead.
    final t = (elapsed.inMilliseconds % 800) / 800;
    final x = db != null
        ? ((db - _floorDb) / -_floorDb).clamp(0.0, 1.0)
        : t < 0.08
            ? 1.0
            : t > 0.18 && t < 0.24
                ? 0.6
                : 0.05;
    _avg += (x - _avg) * 0.08;
    // A beat is a jump above the recent average loudness.
    final beat = ((x - _avg) * 4).clamp(0.0, 1.0);
    _wave.push(x * 0.35 + beat * 0.65, keep: _points + _lagSamples);
  }

  @override
  void dispose() {
    _playingSub.cancel();
    _ticker.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _WavePainter(_wave, points: _points, lag: _lagSamples));
}

/// Recent loudness samples for [_WavePainter], newest last.
class _Wave extends ChangeNotifier {
  final samples = <double>[];

  /// Samples ever pushed; keeps each spike on the same side while it scrolls.
  int count = 0;

  void push(double v, {required int keep}) {
    samples.add(v);
    count++;
    if (samples.length > keep) samples.removeAt(0);
    notifyListeners();
  }

  void reset() {
    if (samples.isEmpty) return;
    samples.clear();
    notifyListeners();
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.wave, {required this.points, required this.lag})
      : super(repaint: wave);

  final _Wave wave;
  final int points;
  final int lag;

  @override
  void paint(Canvas canvas, Size size) {
    final s = wave.samples;
    if (s.length <= lag) {
      const _PulsePainter().paint(canvas, size);
      return;
    }
    // Same baseline and spike room as the still heartbeat (160 x 40 mock-up).
    final sy = size.height / 40, base = 22 * sy;
    final dx = size.width / (points - 1);
    final shown = s.length - lag;
    final path = Path()..moveTo(0, base);
    for (var j = 0; j < shown; j++) {
      final age = shown - 1 - j; // 0 = newest shown sample, at the right edge
      final up = (wave.count - lag - age).isEven;
      path.lineTo(size.width - age * dx, base + (up ? -16 : 14) * sy * s[j]);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Default_Theme.accentColor2.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => false;
}

/// The first picks as a list with their reasons; "Play all" plays every pick.
class _UpNextList extends StatelessWidget {
  const _UpNextList({required this.picks});
  final List<ForYouPick> picks;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tracks = [for (final (t, _) in picks) t];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: l10n.homeUpNext,
              action: l10n.homePlayAll,
              onAction: () => _play(context, tracks, l10n.homeUpNext, 0)),
          const SizedBox(height: 4),
          for (var i = 0; i < picks.length && i < _shown; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _play(context, tracks, l10n.homeUpNext, i),
              onLongPress: () => showMoreBottomSheet(context, picks[i].$1,
                  showSinglePlay: true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _line))),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LoadImageCached(
                        imageUrl: picks[i].$1.thumbnail.url,
                        width: 46,
                        height: 46,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(picks[i].$1.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Default_Theme.secondoryTextStyleMedium
                                  .merge(const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Default_Theme.primaryColor1))),
                          Text(_artistNames(picks[i].$1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Default_Theme.secondoryTextStyle.merge(
                                  TextStyle(fontSize: 11.5, color: _muted))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: _ReasonChip(recReasonText(l10n, picks[i].$2)),
                    ),
                    NeverSuggestButton(track: picks[i].$1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The library's playlists as cards, ending with a Recently played card
/// that opens the history.
class YourPlaylistsRow extends StatelessWidget {
  const YourPlaylistsRow({super.key});

  static const _cardSize = 124.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _LibraryShortcuts(
      builder: (items) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionHeader(title: l10n.homeYourPlaylists),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: _cardSize + 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _card(items[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(_Shortcut s) {
    return GestureDetector(
      onTap: s.onTap,
      child: SizedBox(
        width: _cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: LoadImageCached(
                  imageUrl: s.image, width: _cardSize, height: _cardSize),
            ),
            const SizedBox(height: 7),
            Text(s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Default_Theme.secondoryTextStyleMedium.merge(
                    const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Default_Theme.primaryColor1))),
            Text(s.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Default_Theme.secondoryTextStyle
                    .merge(TextStyle(fontSize: 11, color: _muted))),
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────

typedef _Shortcut = ({
  String title,
  String meta,
  String image,
  VoidCallback onTap
});

/// Library playlists (at most [maxPlaylists]) plus a Recently played entry
/// that opens the history, for [builder]; nothing when both are empty.
class _LibraryShortcuts extends StatelessWidget {
  const _LibraryShortcuts({required this.builder, this.maxPlaylists});
  final Widget Function(List<_Shortcut> items) builder;
  final int? maxPlaylists;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recent = context.watch<RecentlyCubit>().state.tracks;
    return BlocBuilder<LibraryItemsCubit, LibraryItemsState>(
      builder: (context, lib) {
        final items = <_Shortcut>[
          for (final p in lib.playlists.take(maxPlaylists ?? 1 << 30))
            (
              title: p.playlistName,
              meta: p.subTitle ?? '',
              image: p.coverImgUrl ?? '',
              onTap: () => openLibraryItem(context, p),
            ),
          if (recent.isNotEmpty)
            (
              title: l10n.homeRecentlyPlayed,
              meta: l10n.homeAuto,
              image: recent.first.thumbnail.url,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HistoryView())),
            ),
        ];
        return items.isEmpty ? const SizedBox.shrink() : builder(items);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, this.hint, this.action, this.onAction});
  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Default_Theme.secondoryTextStyleMedium.merge(
                      const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Default_Theme.primaryColor1))),
            ),
            if (action != null)
              GestureDetector(
                onTap: onAction,
                child: Text(action!,
                    style: Default_Theme.secondoryTextStyle.merge(
                        const TextStyle(
                            fontSize: 13, color: Default_Theme.accentColor2))),
              ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!,
                style: Default_Theme.secondoryTextStyle
                    .merge(TextStyle(fontSize: 12, color: _muted))),
          ),
      ],
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip(this.text, {this.maxLines = 1});
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Default_Theme.accentColor2.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: Default_Theme.secondoryTextStyle.merge(const TextStyle(
              fontSize: 10.5, color: Default_Theme.accentColor2))),
    );
  }
}

class _RoundPlayButton extends StatelessWidget {
  const _RoundPlayButton(
      {required this.size, required this.playing, this.glow = false});
  final double size;
  final bool playing;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Default_Theme.accentColor2,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: Default_Theme.accentColor2.withValues(alpha: 0.55),
                  blurRadius: 28,
                ),
              ]
            : null,
      ),
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * 0.55,
      ),
    );
  }
}

// ── For you picks (shared by all layouts) ─────────────────────────────────

/// One "For you" pick: the track and why it was suggested.
typedef ForYouPick = (Track, RecReason);

/// The picks as JSON, with just what the cards need to show and play.
String encodeForYou(String seedId, DateTime at, List<ForYouPick> picks) =>
    jsonEncode({
      'seed': seedId,
      'at': at.toUtc().toIso8601String(),
      'picks': [
        for (final (t, r) in picks)
          {
            'id': t.id,
            'title': t.title,
            'artists': [
              for (final a in t.artists) {'id': a.id, 'name': a.name}
            ],
            'thumb': {
              'url': t.thumbnail.url,
              'low': t.thumbnail.urlLow,
              'high': t.thumbnail.urlHigh,
              'layout': t.thumbnail.layout.name,
            },
            'explicit': t.isExplicit,
            'ms': t.durationMs?.toString(),
            'kind': r.kind.name,
            'subject': r.subject,
          }
      ],
    });

/// The picks saved by [encodeForYou], or null when [raw] is missing, for a
/// different seed, older than [maxAge] or unreadable.
List<ForYouPick>? decodeForYou(String? raw, String seedId, DateTime now,
    {Duration maxAge = const Duration(hours: 6)}) {
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final at = DateTime.parse(m['at'] as String);
    if (m['seed'] != seedId || now.toUtc().difference(at) > maxAge) {
      return null;
    }
    return [
      for (final p in (m['picks'] as List).cast<Map<String, dynamic>>())
        (
          Track(
            id: p['id'] as String,
            title: p['title'] as String,
            artists: [
              for (final a
                  in (p['artists'] as List).cast<Map<String, dynamic>>())
                ArtistSummary(id: a['id'] as String, name: a['name'] as String)
            ],
            thumbnail: Artwork(
              url: p['thumb']['url'] as String,
              urlLow: p['thumb']['low'] as String?,
              urlHigh: p['thumb']['high'] as String?,
              layout: ImageLayout.values.byName(p['thumb']['layout'] as String),
            ),
            isExplicit: p['explicit'] as bool,
            durationMs:
                p['ms'] == null ? null : BigInt.tryParse(p['ms'] as String),
          ),
          RecReason(RecReasonKind.values.byName(p['kind'] as String),
              p['subject'] as String),
        )
    ];
  } catch (_) {
    return null;
  }
}

/// On-device recommendations seeded by the most recently played track,
/// shown by [builder] in the current layout's style.
/// Starts once Home's sections have loaded ([homeReady]) so it does not
/// queue ahead of them on the same plugin, and keeps its result on the
/// device for 6 hours per seed, so most launches make no plugin calls.
class ForYouRow extends StatefulWidget {
  const ForYouRow({super.key, required this.homeReady, required this.builder});
  final bool homeReady;
  final Widget Function(List<ForYouPick> picks) builder;

  @override
  State<ForYouRow> createState() => _ForYouRowState();
}

class _ForYouRowState extends State<ForYouRow> {
  String? _key;
  Future<List<ForYouPick>>? _future;

  Future<List<ForYouPick>> _load(Track seed, List<Track> recent) async {
    final settings = SettingsDAO(DBProvider.db);
    await SuggestionBlocklist.load(); // cached picks are filtered by it
    final saved = decodeForYou(
        await settings.getSettingStr(SettingKeys.forYouCache),
        seed.id,
        DateTime.now());
    if (saved != null) return saved;
    try {
      final plugins = ServiceLocator.pluginService;
      final matcher = CrossPluginResolver(pluginService: plugins);
      final ranker = RecommendationRanker(matcher);
      // Plugin calls queue per plugin, and a radio call took 26 s on the
      // realme 5 Pro, past the gatherer's 8 s default. Nothing waits on this.
      final gathered = await CandidateGatherer(plugins, matcher,
              timeout: const Duration(seconds: 60))
          .gather(seed);
      final taste = await RelatedSongsManager.tasteFromDevice(ranker);
      final picks = [
        for (final r in ranker.rank(
          seed: seed,
          candidates: gathered.candidates,
          taste: taste,
          excludeSongKeys: {for (final t in recent) ranker.songKey(t)},
          take: 10,
        ))
          (r.track, r.reason)
      ];
      if (picks.isNotEmpty) {
        await settings.putSettingStr(SettingKeys.forYouCache,
            encodeForYou(seed.id, DateTime.now(), picks));
      }
      return picks;
    } catch (e) {
      debugPrint('For you failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Plugins load after the first frame; gathering before that finds none.
    final resolvers = context
        .select<PluginBloc, int>((b) => b.state.loadedContentResolvers.length);
    return BlocBuilder<RecentlyCubit, RecentlyCubitState>(
      builder: (context, state) {
        if (state.tracks.isEmpty || resolvers == 0 || !widget.homeReady) {
          return const SizedBox.shrink();
        }
        final seed = state.tracks.first;
        final key = '${seed.id}|$resolvers';
        if (key != _key) {
          _key = key;
          _future = _load(seed, state.tracks);
        }
        return FutureBuilder<List<ForYouPick>>(
          future: _future,
          builder: (context, snap) => StreamBuilder<Set<String>>(
            // A pick blocked with the minus button disappears at once.
            stream: SuggestionBlocklist.keys,
            builder: (context, blocked) {
              final picks = [
                for (final p in snap.data ?? const <ForYouPick>[])
                  if (!(blocked.data ?? const {})
                      .contains(SuggestionBlocklist.keyOf(p.$1)))
                    p
              ];
              return picks.isEmpty
                  ? const SizedBox.shrink()
                  : widget.builder(picks);
            },
          ),
        );
      },
    );
  }
}
