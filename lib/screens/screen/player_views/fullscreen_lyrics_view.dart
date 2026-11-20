import 'dart:async';
import 'dart:ui';
import 'package:Bloomee/blocs/lyrics/lyrics_cubit.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/mini_player/mini_player_cubit.dart';
import 'package:Bloomee/core/models/lyrics_models.dart' show Lyrics;
import 'package:Bloomee/screens/screen/player_views/lyrics_search.dart';
import 'package:Bloomee/screens/widgets/media_metadata_links.dart';
import 'package:Bloomee/screens/widgets/play_pause_widget.dart';
import 'package:Bloomee/screens/widgets/sign_board_widget.dart';
import 'package:Bloomee/screens/widgets/up_next_panel.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/utils/load_image.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:rxdart/rxdart.dart';
import 'package:Bloomee/screens/widgets/jarx_loading_indicator.dart';

class FullscreenLyricsView extends StatefulWidget {
  const FullscreenLyricsView({super.key});

  @override
  State<FullscreenLyricsView> createState() => _FullscreenLyricsViewState();
}

class _FullscreenLyricsViewState extends State<FullscreenLyricsView> {
  bool _showControls = true;
  Timer? _hideControlsTimer;
  final UpNextPanelController _upNextPanelController = UpNextPanelController();

  /// How far the lyrics are moved: positive = earlier, negative = later.
  Duration _lyricOffset = Duration.zero;
  bool _isSyncMode = false;
  Timer? _holdTimer;
  late final LyricsCubit _lyricsCubit;

  /// The lyrics being synced and their saved delay, so a change is saved
  /// on Done, on Back and when the next song starts.
  Lyrics? _syncLyrics;
  String? _syncTrackId;
  int _savedOffsetMs = 0;


  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  String? _currentTrackId;

  @override
  void initState() {
    super.initState();
    _startHideControlsTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final playerCubit = context.read<BloomeePlayerCubit>();
    _currentTrackId = playerCubit.bloomeePlayer.currentTrackInfo.id;
    _lyricsCubit = context.read<LyricsCubit>();

    _loadPersistedOffset();
  }

  void _startSync() {
    final state = _lyricsCubit.state;
    if (state is LyricsLoaded && state.lyrics.mediaID == _currentTrackId) {
      _syncLyrics = state.lyrics;
      _syncTrackId = _currentTrackId;
      _savedOffsetMs = state.lyrics.offset ?? 0;
    }
    setState(() {
      _isSyncMode = true;
      _showControls = true;
    });
  }

  /// Saves the delay if it changed.
  void _saveOffset() {
    final lyrics = _syncLyrics, id = _syncTrackId;
    final ms = _lyricOffset.inMilliseconds;
    if (lyrics == null || id == null || ms == _savedOffsetMs) return;
    _savedOffsetMs = ms;
    _lyricsCubit.setLyricsToDB(lyrics, id, offset: ms);
  }

  void _finishSync() {
    _saveOffset();
    _syncLyrics = null;
    setState(() => _isSyncMode = false);
    _startHideControlsTimer();
  }

  /// Sync by tapping a line the moment it's heard: that line's time minus
  /// when it was heard is the delay, however big.
  void _syncToLine(Duration lineStart) {
    final position =
        context.read<BloomeePlayerCubit>().bloomeePlayer.engine.position;
    setState(() => _lyricOffset = lyricsSyncOffset(lineStart, position));
    _onInteraction();
  }

  void _loadPersistedOffset() {
    final lyricsState = context.read<LyricsCubit>().state;
    if (lyricsState is LyricsLoaded &&
        lyricsState.lyrics.mediaID == _currentTrackId) {
      final offsetMs = lyricsState.lyrics.offset ?? 0;
      if (mounted) {
        setState(() {
          _lyricOffset = Duration(milliseconds: offsetMs);
        });
      }
    }
  }

  @override
  void dispose() {
    _saveOffset(); // left with Back while syncing
    _holdTimer?.cancel();
    _hideControlsTimer?.cancel();
    _positionNotifier.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls && !_isSyncMode) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _onInteraction() {
    if (!_showControls) setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  /// Earlier (+) or Later (−) by [ms]; held, it keeps going.
  void _startOffsetChange(int ms) {
    _holdTimer?.cancel();
    setState(() => _lyricOffset += Duration(milliseconds: ms));
    _holdTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      setState(() => _lyricOffset += Duration(milliseconds: ms));
    });
  }

  void _stopOffsetChange() => _holdTimer?.cancel();

  void _openSettingsMenu(LyricsState state, BloomeePlayerCubit playerCubit) {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LyricsSettingsBottomSheet(
        state: state,
        onSyncTap: () {
          Navigator.pop(context);
          _startSync();
        },
      ),
    ).then((_) => _startHideControlsTimer());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bloomeePlayerCubit = context.read<BloomeePlayerCubit>();
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            _buildBackground(bloomeePlayerCubit),
            Container(color: Colors.black.withValues(alpha: 0.4)),
            Positioned.fill(
              child: BlocBuilder<LyricsCubit, LyricsState>(
                builder: (context, state) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: switch (state) {
                      LyricsInitial() => const Center(
                          child: JarxLoadingIndicator(
                              color: Default_Theme.accentColor2)),
                      LyricsLoading() => const Center(
                          child: JarxLoadingIndicator(
                              color: Default_Theme.accentColor2)),
                      LyricsLoaded() => state.lyrics.parsedLyrics != null
                          ? FullscreenSyncedLyrics(
                              state: state,
                              positionNotifier: _positionNotifier,
                              lyricOffset: _lyricOffset,
                              onSyncTap: _isSyncMode ? _syncToLine : null,
                              onInteraction: _onInteraction,
                              isDesktop: isDesktop,
                            )
                          : state.lyrics.lyricsPlain.isNotEmpty
                              ? _buildPlainLyrics(state, isDesktop)
                              : SignBoardWidget(
                                  icon: MingCute.music_2_line,
                                  message: l10n.playerNoLyricsFound),
                      LyricsError() => SignBoardWidget(
                          icon: MingCute.music_2_line,
                          message: l10n.playerNoLyricsFound),
                      LyricsState() => const SizedBox.shrink(),
                    },
                  );
                },
              ),
            ),
            BlocListener<LyricsCubit, LyricsState>(
              listener: (context, state) {
                if (state is LyricsLoading || state is LyricsLoaded) {
                  final newTrackId = state.track.id;
                  if (_currentTrackId != newTrackId) {
                    _saveOffset(); // the last song's delay, if being synced
                    _syncLyrics = null;
                    _currentTrackId = newTrackId;
                    if (mounted) {
                      setState(() {
                        _lyricOffset = Duration.zero;
                        _isSyncMode = false;
                      });
                    }
                  }
                }

                if (state is LyricsLoaded &&
                    state.lyrics.mediaID == _currentTrackId) {
                  final offsetMs = state.lyrics.offset ?? 0;
                  if (mounted) {
                    setState(() {
                      _lyricOffset = Duration(milliseconds: offsetMs);
                    });
                  }
                }
              },
              child: const SizedBox.shrink(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              top: _showControls ? 0 : -150,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                child: _buildTopBar(bloomeePlayerCubit, isDesktop),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              bottom: _showControls ? 0 : -200,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                child: _buildBottomControls(bloomeePlayerCubit, isDesktop),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              // Off screen entirely when not syncing (the panel is ~200 px
              // tall; -100 left half of it showing over the controls).
              bottom: _isSyncMode
                  ? (_showControls
                      ? (isDesktop ? 220 : 250)
                      : (isDesktop ? 80 : 100))
                  : -400,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_isSyncMode,
                child: GestureDetector(
                  onTap: () {},
                  child: _buildSyncControls(),
                ),
              ),
            ),
            UpNextPanel(
              controller: _upNextPanelController,
              peekHeight: 60,
              parentHeight: MediaQuery.of(context).size.height,
              canBeHidden: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(BloomeePlayerCubit bloomeePlayerCubit) {
    return StreamBuilder<MediaItem?>(
      stream: bloomeePlayerCubit.bloomeePlayer.mediaItem,
      builder: (context, snapshot) {
        final currentTrack = bloomeePlayerCubit.bloomeePlayer.currentTrackInfo;
        final artworkUrl =
            currentTrack.thumbnail.urlLow ?? currentTrack.thumbnail.url;

        return AnimatedSwitcher(
          // FIX M-10: Reduced transition duration from 1000ms to 500ms for
          // a snappier background crossfade.
          duration: const Duration(milliseconds: 500),
          child: Container(
            key: ValueKey(snapshot.data?.id),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (artworkUrl.isNotEmpty)
                  Transform.scale(
                    scale: 1.2,
                    child: ImageFiltered(
                      // FIX M-10: Reduced from sigma=80 to sigma=22.
                      // The blur background is overlaid with a 0.6 opacity
                      // black layer — the visual difference from reducing blur
                      // radius is imperceptible while GPU load drops ~3x on
                      // mid-range Android devices (Snapdragon 600/700 series).
                      imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: getImageProviderSync(artworkUrl,
                                fallbackUrl: currentTrack.thumbnail.url),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(color: Colors.black.withValues(alpha: 0.6)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BloomeePlayerCubit bloomeePlayerCubit, bool isDesktop) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 16, 16, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: bloomeePlayerCubit.bloomeePlayer.mediaItem,
                  builder: (context, snapshot) {
                    final currentTrack =
                        bloomeePlayerCubit.bloomeePlayer.currentTrackInfo;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          currentTrack.title,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'NotoSans'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        TrackMetadataLinks(
                          track: currentTrack,
                          showAlbum: currentTrack.album != null,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: isDesktop ? 15 : 13,
                              fontFamily: 'NotoSans',
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              BlocBuilder<LyricsCubit, LyricsState>(
                builder: (context, state) {
                  return IconButton(
                    onPressed: () =>
                        _openSettingsMenu(state, bloomeePlayerCubit),
                    icon: const Icon(MingCute.more_2_fill,
                        color: Colors.white, size: 28),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Syncing the lyrics: tap a line the moment it's heard (precise, any
  /// size of delay), or nudge them Earlier / Later 0.1 s at a time (hold to
  /// keep going). Saved on Done, on Back and when the song changes.
  Widget _buildSyncControls() {
    Widget nudge(String label, IconData icon, int ms, {bool iconFirst = true}) {
      final children = [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ];
      return GestureDetector(
        onTapDown: (_) => _startOffsetChange(ms),
        onTapUp: (_) => _stopOffsetChange(),
        onTapCancel: _stopOffsetChange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              children: iconFirst ? children : children.reversed.toList()),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            // Solid, no backdrop blur: a blur over the moving, faded lyric
            // list smeared it into copies on the realme 5 Pro (Adreno 616).
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xF0161216),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(lyricsDelayLabel(_lyricOffset),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Tap a line the moment you hear it start',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      nudge('Earlier', Icons.arrow_back_rounded, 100),
                      TextButton(
                        onPressed: () =>
                            setState(() => _lyricOffset = Duration.zero),
                        child: Text('Reset',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600)),
                      ),
                      nudge('Later', Icons.arrow_forward_rounded, -100,
                          iconFirst: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Default_Theme.accentColor2,
                          shape: const StadiumBorder()),
                      onPressed: _finishSync,
                      child: const Text('Done',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(
      BloomeePlayerCubit bloomeePlayerCubit, bool isDesktop) {
    final l10n = AppLocalizations.of(context)!;
    final musicPlayer = bloomeePlayerCubit.bloomeePlayer;
    final paddingBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 40, 24, paddingBottom > 0 ? paddingBottom : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => musicPlayer.skipToPrevious(),
                    icon: const Icon(MingCute.skip_previous_fill,
                        color: Colors.white),
                    iconSize: isDesktop ? 40 : 36,
                  ),
                  const SizedBox(width: 32),
                  BlocBuilder<MiniPlayerCubit, MiniPlayerState>(
                    builder: (context, state) {
                      return PlayPauseButton(
                        size: isDesktop ? 80 : 70,
                        onPause: () => musicPlayer.pause(),
                        onPlay: () => musicPlayer.play(),
                        isPlaying: state.isPlaying,
                      );
                    },
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    onPressed: () => musicPlayer.skipToNext(),
                    icon: const Icon(MingCute.skip_forward_fill,
                        color: Colors.white),
                    iconSize: isDesktop ? 40 : 36,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => _upNextPanelController.toggle(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(30)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(MingCute.playlist_fill,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(l10n.upNextTitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlainLyrics(LyricsState state, bool isDesktop) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0.0, 0.2, 0.8, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.35,
            horizontal: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Text(
              state.lyrics.lyricsPlain,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: isDesktop ? 26 : 22,
                  fontFamily: 'NotoSans',
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.8),
            ),
          ),
        ),
      ),
    );
  }
}

/// People tap a little after they hear a line begin; this much is taken off
/// a tap. ponytail: a fixed guess; tune it if taps land late or early.
const lyricsTapReaction = Duration(milliseconds: 150);

/// The delay that puts [lineStart] (the line's time in the lyrics) where
/// it was heard: tapped at [position] in the song. Positive = lyrics
/// earlier, negative = later. Rounded to 0.01 s.
Duration lyricsSyncOffset(Duration lineStart, Duration position) {
  final ms = (lineStart - (position - lyricsTapReaction)).inMilliseconds;
  return Duration(milliseconds: (ms / 10).round() * 10);
}

/// "Lyrics in time", "Lyrics 1.2 s earlier", "Lyrics 0.8 s later".
String lyricsDelayLabel(Duration offset) {
  final ms = offset.inMilliseconds;
  if (ms.abs() < 50) return 'Lyrics in time';
  final s = (ms.abs() / 1000).toStringAsFixed(ms.abs() < 10000 ? 1 : 0);
  return ms > 0 ? 'Lyrics $s s earlier' : 'Lyrics $s s later';
}

class FullscreenSyncedLyrics extends StatefulWidget {
  final LyricsState state;
  final ValueNotifier<Duration> positionNotifier;
  final Duration lyricOffset;

  /// Syncing: a tapped line's start time (instead of seeking to it).
  final void Function(Duration lineStart)? onSyncTap;
  final VoidCallback? onInteraction;
  final bool isDesktop;

  const FullscreenSyncedLyrics({
    required this.state,
    required this.positionNotifier,
    required this.lyricOffset,
    this.onSyncTap,
    this.onInteraction,
    this.isDesktop = false,
    super.key,
  });

  @override
  State<FullscreenSyncedLyrics> createState() => _FullscreenSyncedLyricsState();
}

class _FullscreenSyncedLyricsState extends State<FullscreenSyncedLyrics> {
  StreamSubscription? _positionSubscription;
  StreamSubscription? _indexSubscription;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  int _currentIndex = -1;
  bool _userScrolling = false;
  Timer? _userScrollTimer;

  @override
  void initState() {
    super.initState();
    _setupPositionListener();
  }

  @override
  void didUpdateWidget(FullscreenSyncedLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyricOffset != widget.lyricOffset) _forceSyncRecalculation();
  }

  void _forceSyncRecalculation() {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer.engine;
    final adjustedPosition = player.position + widget.lyricOffset;
    widget.positionNotifier.value = adjustedPosition;

    final newIndex = _findCurrentLyricIndex(adjustedPosition);
    if (newIndex != _currentIndex && newIndex != -1) {
      setState(() => _currentIndex = newIndex);
      _scrollToCurrentLyric();
    }
  }

  void _setupPositionListener() {
    final bloomeePlayerCubit = context.read<BloomeePlayerCubit>();
    final posStream = bloomeePlayerCubit.bloomeePlayer.engine.positionStream;

    _positionSubscription = posStream.listen((rawPosition) {
      if (!mounted) return;
      // Update positionNotifier at full rate for smooth karaoke fill
      widget.positionNotifier.value = rawPosition + widget.lyricOffset;
    });

    // Separate throttled subscription for index changes + scrolling
    _indexSubscription = posStream
        .throttleTime(const Duration(milliseconds: 200))
        .listen((rawPosition) {
      if (!mounted) return;
      final adjustedPosition = rawPosition + widget.lyricOffset;
      final newIndex = _findCurrentLyricIndex(adjustedPosition);
      if (newIndex != _currentIndex && newIndex != -1) {
        setState(() => _currentIndex = newIndex);
        _scrollToCurrentLyric();
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _indexSubscription?.cancel();
    _userScrollTimer?.cancel();
    super.dispose();
  }

  int _findCurrentLyricIndex(Duration currentPosition) {
    final lyrics = widget.state.lyrics.parsedLyrics?.lyrics;
    if (lyrics == null || lyrics.isEmpty) return 0;
    if (currentPosition < lyrics[0].start) return 0;
    if (currentPosition >= lyrics.last.start) return lyrics.length - 1;
    for (int i = 0; i < lyrics.length; i++) {
      final nextStart =
          i + 1 < lyrics.length ? lyrics[i + 1].start : const Duration(days: 1);
      if (currentPosition >= lyrics[i].start && currentPosition < nextStart)
        return i;
    }
    return lyrics.length - 1;
  }

  void _scrollToCurrentLyric() {
    if (_userScrolling) return;
    if (_itemScrollController.isAttached && _currentIndex >= 0) {
      _itemScrollController.scrollTo(
          index: _currentIndex,
          alignment: 0.4,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutQuart);
    }
  }

  void _onUserScroll() {
    widget.onInteraction?.call();
    _userScrolling = true;
    _userScrollTimer?.cancel();
    _userScrollTimer = Timer(const Duration(seconds: 4), () {
      _userScrolling = false;
      _scrollToCurrentLyric();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.state.lyrics.parsedLyrics?.lyrics ?? [];

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) _onUserScroll();
        return false;
      },
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent
            ],
            stops: [0.0, 0.25, 0.75, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          itemCount: lyrics.length,
          padding: EdgeInsets.symmetric(
              vertical: MediaQuery.of(context).size.height * 0.4,
              horizontal: widget.isDesktop ? 64 : 24),
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          itemBuilder: (context, index) {
            final isCurrentLine = index == _currentIndex;
            final isPastLine = index < _currentIndex;
            final lyric = lyrics[index];
            final nextStart = index + 1 < lyrics.length
                ? lyrics[index + 1].start
                : lyric.start + const Duration(seconds: 5);

            return GestureDetector(
              onTap: () {
                widget.onInteraction?.call();
                final sync = widget.onSyncTap;
                if (sync != null) return sync(lyric.start);
                context
                    .read<BloomeePlayerCubit>()
                    .bloomeePlayer
                    .seek(lyric.start - widget.lyricOffset);
              },
              child: _KaraokeLyricLine(
                text: lyric.text,
                startTime: lyric.start,
                endTime: nextStart,
                isActive: isCurrentLine,
                isPast: isPastLine,
                positionNotifier: widget.positionNotifier,
                isDesktop: widget.isDesktop,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// FIX M-08: Removed the TweenAnimationBuilder that had begin==end (the
/// animation never executed). The ShaderMask is now driven directly by the
/// ValueListenableBuilder from positionNotifier, which already updates at the
/// engine's position stream rate (~60Hz). This produces naturally smooth karaoke
/// fill animation without the no-op tween layer.
class _KaraokeLyricLine extends StatelessWidget {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool isActive;
  final bool isPast;
  final ValueNotifier<Duration> positionNotifier;
  final bool isDesktop;

  const _KaraokeLyricLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.isActive,
    required this.isPast,
    required this.positionNotifier,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
        fontSize: isDesktop ? 32 : 28,
        fontFamily: 'NotoSans',
        fontWeight: FontWeight.w800,
        height: 1.4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: RepaintBoundary(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: AnimatedScale(
              // The line being sung grows a little; the others step back.
              scale: isActive ? 1.0 : 0.92,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isActive ? 1.0 : (isPast ? 0.25 : 0.4),
                child: isActive
                    ? ValueListenableBuilder<Duration>(
                        valueListenable: positionNotifier,
                        builder: (context, currentPosition, child) {
                          final elapsed = currentPosition.inMilliseconds -
                              startTime.inMilliseconds;
                          final total =
                              endTime.inMilliseconds - startTime.inMilliseconds;
                          final double progress = total > 0
                              ? (elapsed / total).clamp(0.0, 1.0)
                              : 1.0;

                          // FIX M-08: Direct ShaderMask with current progress.
                          // No TweenAnimationBuilder needed — positionNotifier
                          // already provides smooth sub-second updates.
                          return ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.white.withValues(alpha: 0.35)
                                ],
                                stops: [
                                  progress,
                                  (progress + 0.05).clamp(0.0, 1.0)
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcIn,
                            child: child!,
                          );
                        },
                        child: Text(text,
                            textAlign: TextAlign.center, style: textStyle),
                      )
                    : Text(text,
                        textAlign: TextAlign.center,
                        style: textStyle.copyWith(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsSettingsBottomSheet extends StatelessWidget {
  final LyricsState state;
  final VoidCallback onSyncTap;

  const _LyricsSettingsBottomSheet(
      {required this.state, required this.onSyncTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF151515).withValues(alpha: 0.8),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 32),
            _buildMenuItem(
              icon: MingCute.search_2_line,
              title: l10n.lyricsSettingsSearchTitle,
              subtitle: l10n.lyricsSettingsSearchSubtitle,
              onTap: () {
                Navigator.pop(context);
                showSearch(
                  context: context,
                  delegate: LyricsSearchDelegate(
                    mediaID: state.track.id,
                    searchFieldLabelText: l10n.lyricsSearchFieldLabel,
                  ),
                  query: buildLyricsSearchSeedQuery(
                    title: state.track.title,
                    artists: state.track.artists
                        .map((artist) => artist.name)
                        .toList(),
                    album: state.track.album?.title,
                  ),
                );
              },
            ),
            _buildMenuItem(
              icon: MingCute.time_line,
              title: l10n.lyricsSettingsSyncTitle,
              subtitle: l10n.lyricsSettingsSyncSubtitle,
              color: Default_Theme.accentColor2,
              onTap: onSyncTap,
            ),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: Colors.white12)),
            _buildMenuItem(
              icon: MingCute.save_2_line,
              title: l10n.lyricsSettingsSaveTitle,
              subtitle: l10n.lyricsSettingsSaveSubtitle,
              onTap: () {
                context
                    .read<LyricsCubit>()
                    .setLyricsToDB(state.lyrics, state.track.id);
                Navigator.pop(context);
              },
            ),
            _buildMenuItem(
              icon: MingCute.delete_3_line,
              title: l10n.lyricsSettingsDeleteTitle,
              subtitle: l10n.lyricsSettingsDeleteSubtitle,
              color: const Color(0xFFFF5252),
              onTap: () {
                context.read<LyricsCubit>().deleteLyricsFromDB(state.track);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color color = Colors.white}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13)),
                ],
              ),
            ),
            Icon(MingCute.right_line,
                color: Colors.white.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}
