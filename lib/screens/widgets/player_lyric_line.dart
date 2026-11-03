import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:Bloomee/blocs/lyrics/lyrics_cubit.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/lyrics_models.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/screens/screen/player_views/fullscreen_lyrics_view.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart'
    show scriptOf;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// When each word of a line starts, spreading the line's time over its
/// words by length (plus a little per word for the gap). Synced lyrics only
/// time whole lines, so this is an estimate: close for most songs, a bit
/// early or late on long held notes.
List<Duration> wordStarts(List<String> words, Duration start, Duration end) {
  if (words.isEmpty) return const [];
  // The last ~15% of a line is usually a held note or a breath.
  final span = (end - start).inMilliseconds * 0.85;
  final weights = [for (final w in words) w.length + 2];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final out = <Duration>[];
  var acc = 0;
  for (final w in weights) {
    out.add(start + Duration(milliseconds: (span * acc / total).round()));
    acc += w;
  }
  return out;
}

/// Index of the line being sung at [pos], or -1 before the first line.
int lyricIndexAt(List<ParsedLyric> lines, Duration pos) {
  var lo = 0, hi = lines.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (lines[mid].start <= pos) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}

enum _Entrance { fadeUp, blurIn, pop, slideLeft, slideRight, cascade }

/// The line being sung, shown in the player between the cover and the song
/// title (like Spotify). Words light up as they are sung; each new line comes
/// in with a different animation. Tap it for the full lyrics. Takes no space
/// when the song has no synced lyrics.
class PlayerLyricLine extends StatefulWidget {
  const PlayerLyricLine({super.key});

  @override
  State<PlayerLyricLine> createState() => _PlayerLyricLineState();
}

class _PlayerLyricLineState extends State<PlayerLyricLine> {
  final _position = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _sub;
  int _index = -1;
  _Entrance _entrance = _Entrance.fadeUp;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _sub = context
        .read<BloomeePlayerCubit>()
        .bloomeePlayer
        .engine
        .positionStream
        .listen((p) => _position.value = p);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _position.dispose();
    super.dispose();
  }

  void _pickEntrance() {
    final others = [
      for (final e in _Entrance.values)
        if (e != _entrance) e
    ];
    _entrance = others[_random.nextInt(others.length)];
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LyricsCubit, LyricsState>(
      builder: (context, state) {
        final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
        final lines = state is LyricsLoaded &&
                state.track.id == player.currentTrackInfo.id
            ? state.lyrics.parsedLyrics?.lyrics ?? const <ParsedLyric>[]
            : const <ParsedLyric>[];
        final offset = Duration(
            milliseconds: state is LyricsLoaded ? state.lyrics.offset ?? 0 : 0);
        return AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: lines.isEmpty
              ? const SizedBox(width: double.infinity, height: 15)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const FullscreenLyricsView(),
                    transitionsBuilder: (_, a, __, c) =>
                        FadeTransition(opacity: a, child: c),
                    transitionDuration: const Duration(milliseconds: 300),
                  )),
                  child: SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: _position,
                      builder: (context, raw, _) {
                        final pos = raw + offset;
                        final i = lyricIndexAt(lines, pos);
                        if (i != _index) {
                          _index = i;
                          _pickEntrance();
                        }
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, if (current != null) current],
                          ),
                          transitionBuilder: (child, a) =>
                              _transition(child, a, _entrance),
                          child: _LineWords(
                            key: ValueKey('${lines.hashCode}_$i'),
                            text: i < 0 ? '♪' : lines[i].text.trim(),
                            start: i < 0 ? Duration.zero : lines[i].start,
                            end: i < 0
                                ? Duration.zero
                                : (i + 1 < lines.length
                                    ? lines[i + 1].start
                                    : lines[i].start +
                                        const Duration(seconds: 5)),
                            position: pos,
                            cascade: _entrance == _Entrance.cascade,
                          ),
                        );
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }

  static Widget _transition(Widget child, Animation<double> a, _Entrance e) {
    final fade = FadeTransition(opacity: a, child: child);
    switch (e) {
      case _Entrance.fadeUp:
      case _Entrance.cascade:
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(a),
          child: fade,
        );
      case _Entrance.blurIn:
        return AnimatedBuilder(
          animation: a,
          builder: (_, c) => ImageFiltered(
            imageFilter: ImageFilter.blur(
                sigmaX: 8 * (1 - a.value), sigmaY: 8 * (1 - a.value)),
            child: c,
          ),
          child: fade,
        );
      case _Entrance.pop:
        return ScaleTransition(
          alignment: Alignment.centerLeft,
          scale: Tween(begin: 0.8, end: 1.0)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
          child: fade,
        );
      case _Entrance.slideLeft:
      case _Entrance.slideRight:
        final dx = e == _Entrance.slideLeft ? -0.15 : 0.15;
        return SlideTransition(
          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
          child: fade,
        );
    }
  }
}

/// One line, its words lit up as they are sung. With [cascade] the words
/// also drop in one after another as the line appears.
class _LineWords extends StatelessWidget {
  const _LineWords({
    super.key,
    required this.text,
    required this.start,
    required this.end,
    required this.position,
    required this.cascade,
  });
  final String text;
  final Duration start;
  final Duration end;
  final Duration position;
  final bool cascade;

  @override
  Widget build(BuildContext context) {
    final words = text.isEmpty ? const ['♪'] : text.split(RegExp(r'\s+'));
    final starts = wordStarts(words, start, end);
    // English (Latin letters): Sora, 2 points smaller (it read big at 19).
    // Hindi in Devanagari keeps Noto Sans at 19 (Sora has no Devanagari).
    final latin = scriptOf(text) == 'latin';
    final base = TextStyle(
      fontSize: latin ? 17 : 19,
      fontWeight: FontWeight.w800,
      // Variable fonts: set the weight axis too.
      fontVariations: const [FontVariation('wght', 800)],
      height: 1.3,
      fontFamily: latin ? 'Sora' : 'NotoSans',
    );
    final spans = <InlineSpan>[];
    for (var w = 0; w < words.length; w++) {
      final since = (position - starts[w]).inMilliseconds;
      // Unsung words dim; a word brightens over 180 ms as it is sung.
      final lit = since <= 0 ? 0.0 : (since / 180).clamp(0.0, 1.0);
      final color = Color.lerp(
          Default_Theme.primaryColor1.withValues(alpha: 0.38),
          Default_Theme.primaryColor1,
          lit)!;
      spans.add(TextSpan(
          text: w == words.length - 1 ? words[w] : '${words[w]} ',
          style: base.copyWith(color: color)));
    }
    final line = Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (!cascade) return Align(alignment: Alignment.centerLeft, child: line);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ShaderMask(
        // The words appear left to right, like they are being written.
        shaderCallback: (r) => LinearGradient(
          colors: const [Colors.white, Colors.transparent],
          stops: [t, (t + 0.15).clamp(0.0, 1.0)],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: child,
      ),
      child: Align(alignment: Alignment.centerLeft, child: line),
    );
  }
}
