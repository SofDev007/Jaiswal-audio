import 'dart:async';

import 'package:Bloomee/screens/widgets/tip_overlay.dart';
import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/blocs/library/cubit/library_items_cubit.dart';
import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:Bloomee/core/adapters/track_adapter.dart';
import 'package:Bloomee/screens/widgets/player_lyric_line.dart';
import 'package:Bloomee/screens/widgets/player_option_buttons.dart';
import 'package:Bloomee/screens/widgets/gradient_progress_bar.dart';
import 'package:Bloomee/screens/widgets/more_bottom_sheet.dart';
import 'package:Bloomee/screens/widgets/up_next_panel.dart';
import 'package:Bloomee/screens/widgets/media_metadata_links.dart';
import 'package:Bloomee/screens/widgets/marquee_overflow.dart';
import 'package:Bloomee/screens/screen/player_views/segments_sheet.dart';
import 'package:Bloomee/services/bloomee_player.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/screens/widgets/player_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/widgets/player_overlay_wrapper.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:Bloomee/screens/widgets/like_widget.dart';
import 'package:Bloomee/screens/widgets/play_pause_widget.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/utils/download_types.dart';
import 'package:Bloomee/utils/load_image.dart';
import 'package:Bloomee/utils/pallete_generator.dart';
import 'package:responsive_framework/responsive_framework.dart';
import '../../blocs/media_player/bloomee_player_cubit.dart';
import '../../blocs/mini_player/mini_player_cubit.dart';
import 'player_views/fullscreen_lyrics_view.dart';
import 'package:Bloomee/screens/widgets/jarx_loading_indicator.dart';

class AudioPlayerView extends StatefulWidget {
  const AudioPlayerView({super.key});

  @override
  State<AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<AudioPlayerView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UpNextPanelController _upNextPanelController = UpNextPanelController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerOverlayCubit>().registerUpNextPanelCollapse(
          () => _upNextPanelController.collapse(),
          open: () {
            if (!_upNextPanelController.isExpanded) {
              _upNextPanelController.toggle();
            }
          },
        );
      }
    });
  }

  @override
  void dispose() {
    context.read<PlayerOverlayCubit>().unregisterUpNextPanelCollapse();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bloomeePlayerCubit = context.read<BloomeePlayerCubit>();
    final musicPlayer = bloomeePlayerCubit.bloomeePlayer;
    final isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(TABLET);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 12, 4, 9),
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Default_Theme.primaryColor1,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () {
            if (!_upNextPanelController.collapse()) {
              context.read<PlayerOverlayCubit>().hidePlayer();
            }
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              final mi = musicPlayer.mediaItem.valueOrNull;
              if (mi != null) {
                showSegmentsSheet(
                  context,
                  trackId: mi.id,
                  trackDuration: mi.duration ?? Duration.zero,
                  onSeek: (pos) => musicPlayer.seek(pos),
                );
              }
            },
            icon: const Icon(MingCute.list_check_3_line,
                size: 22, color: Default_Theme.primaryColor1),
          ),
          IconButton(
            onPressed: () => showMoreBottomSheet(
                context, musicPlayer.currentMedia,
                onRemoveFromQueue: () => musicPlayer
                    .removeQueueItemAt(musicPlayer.currentQueueIndex)),
            icon: const Icon(MingCute.more_2_fill,
                size: 25, color: Default_Theme.primaryColor1),
          )
        ],
        title: Column(
          children: [
            Text(
              l10n.playerEnjoyingFrom,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Default_Theme.primaryColor1,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ).merge(Default_Theme.secondoryTextStyle),
            ),
            StreamBuilder<String>(
              stream: musicPlayer.queueTitle,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? l10n.playerUnknownQueue,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Default_Theme.primaryColor2,
                    fontSize: 12,
                  ).merge(Default_Theme.secondoryTextStyle),
                );
              },
            ),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(seconds: 1),
        child: isMobile
            ? LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        child: _PlayerUI(
                          musicPlayer: musicPlayer,
                          tabController: _tabController,
                        ),
                      ),
                      UpNextPanel(
                        peekHeight: 60.0,
                        parentHeight: constraints.maxHeight,
                        controller: _upNextPanelController,
                      ),
                    ],
                  );
                },
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 400,
                      maxWidth: MediaQuery.of(context).size.width * 0.60,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _PlayerUI(
                        musicPlayer: musicPlayer,
                        tabController: _tabController,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.8,
                        child: UpNextPanel(
                          peekHeight: 60,
                          parentHeight:
                              MediaQuery.of(context).size.height * 0.8,
                          isDesktopMode: true,
                          controller: _upNextPanelController,
                        ),
                      ),
                    ),
                  )
                ],
              ),
      ),
    );
  }
}

class _PlayerUI extends StatelessWidget {
  final BloomeeMusicPlayer musicPlayer;
  final TabController tabController;

  const _PlayerUI({
    required this.musicPlayer,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: tabController.animation!,
            builder: (context, child) {
              return Opacity(
                opacity: (1 - tabController.animation!.value),
                child: child,
              );
            },
            child: const RepaintBoundary(child: AmbientImgShadowWidget()),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Shuffle / sleep-timer messages pop up just above the cover.
              const SizedBox(
                height: 60,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: PlayerFlash(),
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  // YouTube songs in video mode: the music video instead.
                  child: CoverOrVideo(cover: CoverImageVolSlider()),
                ),
              ),
              // The line being sung (none without synced lyrics).
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: PlayerLyricLine(),
              ),
              // "Play video", just above the song's name.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: TipAnchor(id: 'A4', child: PlayVideoButton()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: PlayerCtrlWidgets(musicPlayer: musicPlayer),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

/// Which way the last skip went (1 = next, -1 = previous), so the title
/// slides in from the same side as the cover.
final ValueNotifier<int> _skipDirection = ValueNotifier(1);

/// The cover: drag it sideways to skip (it tilts, flies off and the next
/// cover comes in from the other side), shrinks a little while paused, and
/// grows out of the mini player as the player opens.
class CoverImageVolSlider extends StatefulWidget {
  const CoverImageVolSlider({super.key});

  @override
  State<CoverImageVolSlider> createState() => _CoverImageVolSliderState();
}

class _CoverImageVolSliderState extends State<CoverImageVolSlider>
    with SingleTickerProviderStateMixin {
  /// Sideways offset of the cover in pixels.
  late final AnimationController _dx =
      AnimationController.unbounded(vsync: this);
  bool _armed = false;
  bool _swiping = false;

  /// Share of the cover's width to drag before letting go skips.
  static const double _skipFraction = 0.28;

  /// Tilt at a full cover-width drag (0.14 rad ≈ 8°).
  static const double _maxTilt = 0.14;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    _dx.stop();
    _dx.value += d.delta.dx;
    final armed = _dx.value.abs() > width * _skipFraction;
    if (armed != _armed) {
      _armed = armed;
      if (armed) HapticFeedback.selectionClick(); // letting go now skips
    }
  }

  Future<void> _onDragEnd(DragEndDetails d, double width) async {
    final v = d.primaryVelocity ?? 0;
    final flung = v.abs() > 700;
    _armed = false;
    if (!flung && _dx.value.abs() <= width * _skipFraction) {
      _dx.animateTo(0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack);
      return;
    }
    final next = flung ? v < 0 : _dx.value < 0;
    final out = (next ? -1.0 : 1.0) * width * 1.2;
    HapticFeedback.mediumImpact();
    _skipDirection.value = next ? 1 : -1;
    setState(() => _swiping = true);
    await _dx.animateTo(out,
        duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
    if (!mounted) return;
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    next ? player.skipToNext() : player.skipToPrevious();
    _dx.value = -out;
    await _dx.animateTo(0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic);
    if (mounted) setState(() => _swiping = false);
  }

  @override
  Widget build(BuildContext context) {
    final bloomeePlayerCubit = context.read<BloomeePlayerCubit>();
    final open = PlayerOpenAnimation.maybeOf(context);

    final cover = StreamBuilder<MediaItem?>(
      stream: bloomeePlayerCubit.bloomeePlayer.mediaItem,
      builder: (context, snapshot) {
        final currentTrack = bloomeePlayerCubit.bloomeePlayer.currentTrackInfo;
        final highResUrl =
            currentTrack.thumbnail.urlHigh ?? currentTrack.thumbnail.url;
        final lowResUrl =
            currentTrack.thumbnail.urlLow ?? currentTrack.thumbnail.url;

        // A new song's cover fades and settles in (a swipe brings it in
        // from the side instead).
        return AnimatedSwitcher(
          duration:
              _swiping ? Duration.zero : const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          // Fill the square: the default Stack lets a small (offline,
          // low-res) thumbnail shrink to its own size.
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1).animate(anim),
              child: child,
            ),
          ),
          child: ClipRRect(
            key: ValueKey(highResUrl),
            borderRadius: BorderRadius.circular(20),
            child: LoadImageCached(
              imageUrl: highResUrl,
              fallbackUrl: lowResUrl,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      Widget art = Center(
        child: AspectRatio(
          aspectRatio: 1.0,
          child: BlocSelector<MiniPlayerCubit, MiniPlayerState, bool>(
            // Loading between songs doesn't count as paused.
            selector: (s) => s.isPlaying || s.isLoading || s.isResolving,
            builder: (context, playing) => AnimatedScale(
              scale: playing ? 1 : 0.92,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              child: cover,
            ),
          ),
        ),
      );
      if (open != null) {
        art = AnimatedBuilder(
          animation: open,
          builder: (context, child) => Transform.scale(
            scale: 0.5 + 0.5 * Curves.easeOutCubic.transform(open.value),
            alignment: Alignment.bottomLeft,
            child: child,
          ),
          child: art,
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
        onHorizontalDragEnd: (d) => _onDragEnd(d, width),
        child: AnimatedBuilder(
          animation: _dx,
          builder: (context, child) => Transform.translate(
            offset: Offset(_dx.value, 0),
            child: Transform.rotate(
              angle: (_dx.value / width).clamp(-1.0, 1.0) * _maxTilt,
              child: child,
            ),
          ),
          child: SizedBox.expand(child: art),
        ),
      );
    });
  }
}

class PlayerCtrlWidgets extends StatelessWidget {
  final BloomeeMusicPlayer musicPlayer;
  const PlayerCtrlWidgets({super.key, required this.musicPlayer});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SongInfoRow(),
        const SizedBox(height: 15),
        const _PlayerProgressBar(),
        const SizedBox(height: 25),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: _PlayerControlsRow(musicPlayer: musicPlayer),
        ),
      ],
    );
  }
}

class _SongInfoRow extends StatelessWidget {
  const _SongInfoRow();

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<MediaItem?>(
            stream: player.mediaItem,
            builder: (context, snapshot) {
              final currentTrack = player.currentTrackInfo;
              // Title and artist slide in from the side the cover came from.
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, anim) {
                  final incoming =
                      child.key == ValueKey('info-${currentTrack.id}');
                  final side = _skipDirection.value * (incoming ? 1 : -1);
                  return ClipRect(
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: Offset(0.35 * side, 0), end: Offset.zero)
                          .animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                  );
                },
                child: Column(
                  key: ValueKey('info-${currentTrack.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeOverflow(
                      key: ValueKey('title-${currentTrack.id}'),
                      child: Text(
                        currentTrack.title,
                        maxLines: 1,
                        style: Default_Theme.secondoryTextStyle
                            .merge(const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Default_Theme.primaryColor1,
                        )),
                      ),
                    ),
                    const SizedBox(height: 4),
                    MarqueeOverflow(
                      key: ValueKey('meta-${currentTrack.id}'),
                      child: TrackMetadataLinks(
                        track: currentTrack,
                        showAlbum: currentTrack.album != null,
                        maxLines: 1,
                        style: Default_Theme.secondoryTextStyle.merge(TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Default_Theme.primaryColor1
                              .withValues(alpha: 0.7),
                        )),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        const _DownloadButton(),
        const _LikeButton(),
      ],
    );
  }
}

/// FIX M-05: Replaced FutureBuilder (re-queries DB on every stream event) with
/// a StatefulWidget that caches the download state and only re-queries when the
/// media item ID actually changes.
class _DownloadButton extends StatefulWidget {
  const _DownloadButton();

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  String? _lastTrackId;
  bool _isDownloaded = false;
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      if (mi?.id != _lastTrackId) {
        _lastTrackId = mi?.id;
        _queryDownloadState(mi);
      }
    });
    // Query immediately for the current track.
    _queryDownloadState(player.mediaItem.valueOrNull);
  }

  Future<void> _queryDownloadState(MediaItem? mi) async {
    if (mi == null) {
      if (mounted) setState(() => _isDownloaded = false);
      return;
    }
    try {
      final info = await context
          .read<DownloaderCubit>()
          .getDownloadInfo(mediaItemToTrack(mi));
      if (mounted) setState(() => _isDownloaded = info != null);
    } catch (_) {
      if (mounted) setState(() => _isDownloaded = false);
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  static const _over = {
    DownloadState.completed,
    DownloadState.failed,
    DownloadState.cancelled,
  };

  @override
  Widget build(BuildContext context) {
    // While the current song downloads: a ring that fills up; when it's
    // done the ring pops into the offline tick.
    return BlocBuilder<DownloaderCubit, DownloaderState>(
      builder: (context, state) {
        final id = _lastTrackId;
        final active = state.downloads
            .where(
                (d) => d.task.song.id == id && !_over.contains(d.status.state))
            .firstOrNull;
        final done = _isDownloaded ||
            (id != null && context.read<DownloaderCubit>().isDownloaded(id));
        final progress = active?.status.progress ?? 0;

        final Widget child;
        if (active != null) {
          child = SizedBox.square(
            key: const ValueKey('dl-active'),
            dimension: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, value, _) => CircularProgressIndicator(
                    value: progress > 0 ? value : null,
                    strokeWidth: 2.5,
                    color: Default_Theme.accentColor2,
                    backgroundColor:
                        Default_Theme.primaryColor1.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
          );
        } else if (done) {
          child = Tooltip(
            key: const ValueKey('dl-done'),
            message: AppLocalizations.of(context)!.tooltipAvailableOffline,
            child: IconButton(
              iconSize: 25,
              icon: Icon(
                Icons.offline_pin_rounded,
                color: Default_Theme.primaryColor1.withValues(alpha: 0.5),
              ),
              onPressed: () {},
            ),
          );
        } else {
          child = const SizedBox.shrink(key: ValueKey('dl-none'));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: child,
        );
      },
    );
  }
}

/// FIX M-05: Replaced nested FutureBuilder+StreamBuilder+BlocBuilder with a
/// StatefulWidget that caches liked state and only re-queries when track ID changes.
class _LikeButton extends StatefulWidget {
  const _LikeButton();

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  String? _lastTrackId;
  bool _isLiked = false;
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      if (mi?.id != _lastTrackId) {
        _lastTrackId = mi?.id;
        _queryLikedState(mi);
      }
    });
    _queryLikedState(player.mediaItem.valueOrNull);
  }

  Future<void> _queryLikedState(MediaItem? mi) async {
    if (mi == null) {
      if (mounted) setState(() => _isLiked = false);
      return;
    }
    try {
      final liked = await context
          .read<LibraryItemsCubit>()
          .isTrackLiked(mediaItemToTrack(mi));
      if (mounted) setState(() => _isLiked = liked);
    } catch (_) {
      if (mounted) setState(() => _isLiked = false);
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<bool>(
      stream: player.engine.playingStream,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;
        final currentMedia = player.mediaItem.valueOrNull;
        if (currentMedia == null) return const SizedBox.shrink();

        return LikeBtnWidget(
          isPlaying: isPlaying,
          isLiked: _isLiked,
          iconSize: 25,
          onLiked: () {
            context
                .read<LibraryItemsCubit>()
                .setTrackLiked(mediaItemToTrack(currentMedia), true);
            setState(() => _isLiked = true);
            SnackbarService.showMessage(l10n.playerLiked(currentMedia.title));
          },
          onDisliked: () {
            context
                .read<LibraryItemsCubit>()
                .setTrackLiked(mediaItemToTrack(currentMedia), false);
            setState(() => _isLiked = false);
            SnackbarService.showMessage(l10n.playerUnliked(currentMedia.title));
          },
        );
      },
    );
  }
}

class _PlayerProgressBar extends StatelessWidget {
  const _PlayerProgressBar();

  @override
  Widget build(BuildContext context) {
    final playerCubit = context.read<BloomeePlayerCubit>();
    return RepaintBoundary(
      child: StreamBuilder<ProgressBarStreams>(
        stream: playerCubit.progressStreams,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return GradientProgressBar.fromAccentColors(
            progress: data?.position ?? Duration.zero,
            total: data?.duration ?? Duration.zero,
            buffered: data?.buffered ?? Duration.zero,
            onSeek: playerCubit.bloomeePlayer.seek,
            isPlaying: data?.isPlaying ?? false,
            activeAccentColor: Default_Theme.accentColor1,
            inactiveAccentColor: Default_Theme.accentColor2,
            activeGradientStyle: GradientStyle.lightAndBreezy,
            inactiveGradientStyle: GradientStyle.warmAndRich,
            trackHeight: 6.0,
            thumbRadius: 8.0,
            timeLabelPadding: 5,
            timeLabelStyle: Default_Theme.secondoryTextStyle.merge(TextStyle(
              fontSize: 15,
              color: Default_Theme.primaryColor1.withValues(alpha: 0.7),
            )),
            timeLabelLocation: TimeLabelLocation.above,
            inactiveTrackColor:
                Default_Theme.primaryColor2.withValues(alpha: 0.1),
            animationDuration: const Duration(milliseconds: 200),
            animationCurve: Curves.easeOutCubic,
          );
        },
      ),
    );
  }
}

class _PlayerControlsRow extends StatelessWidget {
  final BloomeeMusicPlayer musicPlayer;
  const _PlayerControlsRow({required this.musicPlayer});

  Widget _buildControlColumn({required Widget top, required Widget bottom}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 70, alignment: Alignment.center, child: top),
        SizedBox(height: 40, child: bottom),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControlColumn(
          top: const TipAnchor(id: 'T2', child: SleepTimerButton()),
          bottom: const LoopButton(),
        ),
        _buildControlColumn(
          top: IconButton(
            icon: const Icon(MingCute.skip_previous_fill,
                color: Default_Theme.primaryColor1, size: 35),
            onPressed: () {
              _skipDirection.value = -1;
              musicPlayer.skipToPrevious();
            },
          ),
          bottom: const SizedBox(height: 40),
        ),
        _buildControlColumn(
          top: const _PlayPauseButton(),
          bottom: const SizedBox(height: 40),
        ),
        _buildControlColumn(
          top: IconButton(
            icon: const Icon(MingCute.skip_forward_fill,
                color: Default_Theme.primaryColor1, size: 35),
            onPressed: () {
              _skipDirection.value = 1;
              musicPlayer.skipToNext();
            },
          ),
          bottom: const SizedBox(height: 40),
        ),
        _buildControlColumn(
          top: const ShuffleButton(),
          bottom: IconButton(
            icon: const Icon(MingCute.align_center_line,
                color: Default_Theme.primaryColor1, size: 24),
            onPressed: () {
              Navigator.of(context).push(PageRouteBuilder(
                pageBuilder: (_, __, ___) => const FullscreenLyricsView(),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c),
                transitionDuration: const Duration(milliseconds: 300),
              ));
            },
          ),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final musicPlayer = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return BlocBuilder<MiniPlayerCubit, MiniPlayerState>(
      builder: (context, state) {
        Widget child;
        Color buttonColor = Default_Theme.accentColor2;

        if (state.isLoading || state.isResolving) {
          child = const JarxLoadingIndicator(
              strokeWidth: 3, color: Default_Theme.primaryColor1);
          buttonColor = state.isPlaying
              ? Default_Theme.accentColor1
              : Default_Theme.accentColor2;
        } else if (state.isCompleted) {
          child = const Icon(FontAwesome.rotate_right_solid,
              color: Default_Theme.primaryColor1, size: 32);
          buttonColor = Default_Theme.accentColor1;
        } else if (state.hasError) {
          child = const Icon(MingCute.warning_line,
              color: Default_Theme.primaryColor1, size: 32);
        } else if (state.isVisible) {
          return PlayPauseButton(
            size: 70,
            onPause: musicPlayer.pause,
            onPlay: musicPlayer.play,
            isPlaying: state.isPlaying,
          );
        } else {
          child = const SizedBox();
        }

        return GestureDetector(
          onTap: () {
            if (state.isCompleted) {
              musicPlayer.seek(Duration.zero);
              musicPlayer.play();
            } else if (state.hasError) {
              musicPlayer.play();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: [
                BoxShadow(color: buttonColor, spreadRadius: 1, blurRadius: 15)
              ],
            ),
            child: Center(child: SizedBox(width: 32, height: 32, child: child)),
          ),
        );
      },
    );
  }
}

/// FIX M-06: Replaced async palette fetch inside build() with a proper
/// lifecycle-based approach using a stream subscription.
/// The fetch only triggers when the artUri CHANGES, not on every rebuild.
class AmbientImgShadowWidget extends StatefulWidget {
  const AmbientImgShadowWidget({super.key});

  @override
  State<AmbientImgShadowWidget> createState() => _AmbientImgShadowWidgetState();
}

class _AmbientImgShadowWidgetState extends State<AmbientImgShadowWidget> {
  Color? _cachedColor;
  String? _lastArtUri;
  StreamSubscription? _mediaSub;
  bool _fetchingPalette = false;

  @override
  void initState() {
    super.initState();
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      final artUri = mi?.artUri?.toString();
      if (artUri != _lastArtUri) {
        _lastArtUri = artUri;
        _fetchPalette(artUri);
      }
    });
    // Initial fetch
    final current = player.mediaItem.valueOrNull;
    _lastArtUri = current?.artUri?.toString();
    _fetchPalette(_lastArtUri);
  }

  Future<void> _fetchPalette(String? artUri) async {
    if (artUri == null || artUri.isEmpty || _fetchingPalette) return;
    _fetchingPalette = true;
    try {
      final palette = await getPalleteFromImage(artUri);
      if (mounted) {
        setState(() => _cachedColor = palette.dominantColor?.color);
      }
    } catch (_) {
    } finally {
      _fetchingPalette = false;
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              (_cachedColor ?? const Color.fromARGB(255, 163, 44, 115))
                  .withValues(alpha: 0.35),
              Colors.transparent,
            ],
            center: Alignment.center,
            radius: 0.70,
          ),
        ),
      ),
    );
  }
}
