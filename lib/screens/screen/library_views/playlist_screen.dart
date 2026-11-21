import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:Bloomee/screens/widgets/tip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/screens/widgets/shuffle_bubbles.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:icons_plus/icons_plus.dart';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/screens/screen/library_views/cubit/current_playlist_cubit.dart';
import 'package:Bloomee/screens/screen/library_views/more_opts_sheet.dart';
import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/services/downloaded_playlists.dart';
import 'package:Bloomee/screens/widgets/more_bottom_sheet.dart';
import 'package:Bloomee/screens/widgets/animated_list_item.dart';
import 'package:Bloomee/screens/widgets/play_pause_widget.dart';
import 'package:Bloomee/screens/widgets/sign_board_widget.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/screens/widgets/song_tile.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/utils/load_image.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/widgets/jarx_loading_indicator.dart';

part 'playlist_info_dialog.dart';

class PlaylistView extends StatefulWidget {
  final String? initialPlaylistName;

  const PlaylistView({super.key, this.initialPlaylistName});

  @override
  State<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends State<PlaylistView> {
  late final ScrollController _scrollController;
  bool _didTriggerInitialLoad = false;

  bool _loadingAll = false;

  // Search inside the playlist (the whole playlist is loaded when it opens).
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
    if (_searching) {
      unawaited(context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded());
    }
  }

  bool _matches(Track t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.artists.any((a) => a.name.toLowerCase().contains(q)) ||
        (t.album?.title.toLowerCase().contains(q) ?? false);
  }

  Widget _buildSearchField() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(color: Colors.white),
        cursorColor: Default_Theme.accentColor2,
        decoration: InputDecoration(
          hintText: l10n.playlistSearchHint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: Icon(Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.6)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.6)),
                  onPressed: () => setState(() {
                    _query = '';
                    _searchController.clear();
                  }),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  String? _targetPlaylistName;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);

    if (widget.initialPlaylistName != null &&
        widget.initialPlaylistName!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startInitialLoad(widget.initialPlaylistName!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didTriggerInitialLoad) return;

    final playlistName = _targetPlaylistName ??
        widget.initialPlaylistName ??
        context.read<CurrentPlaylistCubit>().currentPlaylistName;
    if (playlistName == null || playlistName.trim().isEmpty) return;

    _didTriggerInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInitialLoad(playlistName);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 500) {
      context.read<CurrentPlaylistCubit>().loadMoreTracks();
    }
  }

  Future<void> _startInitialLoad(String playlistName) async {
    if (!mounted) return;
    _targetPlaylistName = playlistName;
    final cubit = context.read<CurrentPlaylistCubit>();

    await cubit.openPlaylist(playlistName, deferFirstPage: true);
    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    await cubit.loadMoreTracks();
  }

  Future<void> _playFromPlaylist(
      BuildContext context, CurrentPlaylistState state,
      {int? index, bool shuffle = false}) async {
    final fullPlaylist =
        await context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded();
    if (!mounted || fullPlaylist.tracks.isEmpty) return;

    context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
          Playlist(tracks: fullPlaylist.tracks, title: fullPlaylist.title),
          idx: index ?? 0,
          doPlay: true,
          shuffling: shuffle,
        );
  }

  /// The playlist shuffled with suggestions mixed in (one after every 3).
  Future<void> _smartShuffle(BuildContext context) async {
    final fullPlaylist =
        await context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded();
    if (!mounted || fullPlaylist.tracks.isEmpty) return;
    context.read<BloomeePlayerCubit>().bloomeePlayer.smartShuffle(
        Playlist(tracks: fullPlaylist.tracks, title: fullPlaylist.title));
  }

  List<Color> _getOptimizedPalette(BuildContext context) {
    final pallete =
        context.read<CurrentPlaylistCubit>().getCurrentPlaylistPallete();
    Color fgColor = pallete?.lightVibrantColor?.color ?? Colors.white;
    Color bgColor = pallete?.dominantColor?.color ??
        pallete?.darkMutedColor?.color ??
        Default_Theme.themeColor;

    if (bgColor.computeLuminance() / fgColor.computeLuminance() > 0.05) {
      fgColor = HSLColor.fromColor(fgColor)
          .withLightness(
              (HSLColor.fromColor(fgColor).lightness + 0.1).clamp(0.0, 1.0))
          .toColor();
      bgColor = HSLColor.fromColor(bgColor)
          .withLightness(
              (HSLColor.fromColor(bgColor).lightness - 0.1).clamp(0.0, 1.0))
          .toColor();
    }
    return [fgColor, bgColor];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: BlocBuilder<CurrentPlaylistCubit, CurrentPlaylistState>(
        builder: (context, state) {
          final waitingForTarget = _targetPlaylistName != null &&
              state.playlist.title != _targetPlaylistName;

          if (waitingForTarget ||
              state.status == CurrentPlaylistLoadStatus.initial ||
              state.status == CurrentPlaylistLoadStatus.loading) {
            return const Center(
                child: JarxLoadingIndicator(color: Default_Theme.accentColor2));
          }

          if (state.status == CurrentPlaylistLoadStatus.error) {
            return Center(
                child: SignBoardWidget(
                    message: state.errorMessage ?? 'Failed to load playlist',
                    icon: MingCute.alert_line));
          }

          final colors = _getOptimizedPalette(context);
          final fgColor = colors[0];
          final bgColor = colors[1];
          final tracks = state.playlist.tracks;
          final imageUrl = tracks.isNotEmpty
              ? (tracks.first.thumbnail.urlHigh ?? tracks.first.thumbnail.url)
              : '';

          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 850;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildAmbientBackground(imageUrl, bgColor, isMobile),
                  if (isMobile)
                    _buildMobileLayout(
                        state, fgColor, bgColor, imageUrl, l10n, constraints)
                  else
                    _buildDesktopLayout(
                        state, fgColor, bgColor, imageUrl, l10n, constraints),
                ],
              );
            },
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 70,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: Center(
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: IconButton(
            tooltip: AppLocalizations.of(context)!.playlistSearchHint,
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _searching
                    ? Default_Theme.accentColor2.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(
                  _searching ? Icons.close_rounded : Icons.search_rounded,
                  color: Colors.white,
                  size: 20),
            ),
            onPressed: _toggleSearch,
          ),
        ),
      ],
    );
  }

  Widget _buildAmbientBackground(
      String imageUrl, Color dominantColor, bool isMobile) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Default_Theme.themeColor),
            Positioned(
              top: isMobile ? -100 : -200,
              left: isMobile ? -50 : -200,
              width: 800,
              height: 800,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      dominantColor.withValues(alpha: 0.45),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
            if (imageUrl.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.35,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                    child:
                        LoadImageCached(imageUrl: imageUrl, fit: BoxFit.cover),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Default_Theme.themeColor.withValues(alpha: 0.1),
                    Default_Theme.themeColor.withValues(alpha: 0.85),
                    Default_Theme.themeColor,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Pro-Desktop Layout (Perfectly Centered Left Panel) ───

  Widget _buildDesktopLayout(
      CurrentPlaylistState state,
      Color fgColor,
      Color bgColor,
      String imageUrl,
      AppLocalizations l10n,
      BoxConstraints constraints) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // FIXED LEFT PANEL: Centered content, elegant flex scaling
        SizedBox(
          width: math.max(340, constraints.maxWidth * 0.35),
          child: Padding(
            // Optically balanced padding so it sits perfectly in the center of its space
            padding: const EdgeInsets.fromLTRB(40, 90, 20, 40),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Centered alignment
              children: [
                const Spacer(flex: 1), // Top breathing room

                // Intelligently scaling cover art
                Flexible(
                  flex: 10,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: _buildIntelligentCover(imageUrl, bgColor),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Meta Info (Centered)
                _buildInfo(state, l10n, isCentered: true),

                const SizedBox(height: 24),

                // Single-Line Forced Actions (Centered)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child:
                      _buildActions(state, fgColor, bgColor, isCentered: true),
                ),

                const Spacer(flex: 2), // Bottom breathing room
              ],
            ),
          ),
        ),

        // SCROLLABLE RIGHT PANEL: The track list
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(
                20, 90, 40, 40), // Matches left panel gap
            decoration: BoxDecoration(
              color: Default_Theme.themeColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 40,
                    offset: const Offset(0, 15)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _withScrollThumb(CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                      child:
                          _FailedDownloadsBanner(title: state.playlist.title)),
                  if (_searching)
                    SliverToBoxAdapter(child: _buildSearchField()),
                  if (state.playlist.tracks.isEmpty && !state.isLoadingMore)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                          child: SignBoardWidget(
                              message: state.playlist.title == 'Liked'
                                  ? l10n.likedEmptyState
                                  : l10n.playlistEmptyState,
                              icon: MingCute.playlist_line)),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 16),
                      sliver: _buildTrackList(state),
                    ),
                  if (state.isLoadingMore || state.hasMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: JarxLoadingIndicator(
                                color: Default_Theme.accentColor2)),
                      ),
                    ),
                ],
              )),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Mobile Layout (Scrolling Canvas) ───

  Widget _buildMobileLayout(
      CurrentPlaylistState state,
      Color fgColor,
      Color bgColor,
      String imageUrl,
      AppLocalizations l10n,
      BoxConstraints constraints) {
    return _withScrollThumb(CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 100, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth * 0.65,
                  height: constraints.maxWidth * 0.65,
                  child: _buildIntelligentCover(imageUrl, bgColor),
                ),
                const SizedBox(height: 32),
                _buildInfo(state, l10n, isCentered: true),
                const SizedBox(height: 28),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child:
                      _buildActions(state, fgColor, bgColor, isCentered: true),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: _FailedDownloadsBanner(title: state.playlist.title)),
        if (_searching) SliverToBoxAdapter(child: _buildSearchField()),
        if (state.playlist.tracks.isEmpty && !state.isLoadingMore)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child: SignBoardWidget(
                    message: state.playlist.title == 'Liked'
                        ? l10n.likedEmptyState
                        : l10n.playlistEmptyState,
                    icon: MingCute.playlist_line)),
          )
        else
          SliverPadding(
            padding: EdgeInsets.only(bottom: state.isLoadingMore ? 0 : 120),
            sliver: _buildTrackList(state),
          ),
        if (state.isLoadingMore || state.hasMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child:
                      JarxLoadingIndicator(color: Default_Theme.accentColor2)),
            ),
          ),
      ],
    ));
  }

  /// Draggable thumb for jumping through long playlists. Fades in while
  /// scrolling and out when idle; replaces the platform's default scrollbar.
  Widget _withScrollThumb(Widget scrollView) => RawScrollbar(
        controller: _scrollController,
        interactive: true,
        thickness: 6,
        radius: const Radius.circular(3),
        minThumbLength: 56,
        mainAxisMargin: 8,
        crossAxisMargin: 3,
        thumbColor: Default_Theme.accentColor2.withValues(alpha: 0.85),
        fadeDuration: const Duration(milliseconds: 250),
        timeToFade: const Duration(milliseconds: 1200),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: scrollView,
        ),
      );

  Widget _buildIntelligentCover(String imageUrl, Color dominantColor) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black.withValues(alpha: 0.2),
          boxShadow: [
            BoxShadow(
                color: dominantColor.withValues(alpha: 0.35),
                blurRadius: 60,
                offset: const Offset(0, 20)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10)),
            BoxShadow(
                color: Colors.white.withValues(alpha: 0.1),
                blurRadius: 1,
                offset: const Offset(0, -1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: imageUrl.isEmpty
              ? FractionallySizedBox(
                  widthFactor: 0.3,
                  heightFactor: 0.3,
                  child: Icon(MingCute.music_2_line,
                      color: Colors.white.withValues(alpha: 0.3)),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: LoadImageCached(
                          imageUrl: imageUrl, fit: BoxFit.cover),
                    ),
                    Container(color: Colors.black.withValues(alpha: 0.3)),
                    LoadImageCached(imageUrl: imageUrl, fit: BoxFit.contain),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildInfo(CurrentPlaylistState state, AppLocalizations l10n,
      {required bool isCentered}) {
    // Long playlists load a page at a time: load the rest once in the
    // background so the total length counts every song.
    if (state.hasMore && !state.isLoadingMore && !_loadingAll) {
      _loadingAll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
              context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded());
        }
      });
    }
    final creatorText = l10n.playlistByCreator(
        state.playlist.artists?.map((a) => a.name).join(', ') ??
            l10n.playlistYou);

    return Column(
      crossAxisAlignment:
          isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          state.playlist.title,
          textAlign: isCentered ? TextAlign.center : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          [
            l10n.playlistSongCount(state.totalTracks),
            // Total length once every song is loaded ("4h 36min").
            if (!state.hasMore && playlistLength(state.playlist.tracks) != null)
              playlistLength(state.playlist.tracks)!,
          ].join(' · '),
          textAlign: isCentered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          creatorText,
          textAlign: isCentered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(CurrentPlaylistState state, Color fgColor, Color bgColor,
      {required bool isCentered}) {
    final isEmpty = state.playlist.tracks.isEmpty;
    final l10n = AppLocalizations.of(context)!;

    return RepaintBoundary(
      child: Row(
        mainAxisAlignment:
            isCentered ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // Hug contents tightly
        children: [
          Builder(builder: (ctx) {
            final downloaded = ctx.watch<DownloaderCubit>().state.downloaded;
            // Only once the whole playlist is loaded: a long one is loaded a
            // page at a time, and the first page can be all downloaded.
            final allDownloaded = !isEmpty &&
                !state.hasMore &&
                state.playlist.tracks
                    .every((s) => downloaded.any((d) => d.id == s.id));

            if (allDownloaded) {
              // Tapping it records the playlist as downloaded (so Offline
              // shows it as a playlist) and says so; nothing to download.
              return Tooltip(
                message: l10n.playlistAvailableOffline,
                child: GestureDetector(
                  onTap: () => _handleDownload(context, state, l10n),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            Default_Theme.accentColor2.withValues(alpha: 0.15)),
                    child: const Icon(Icons.offline_pin_rounded,
                        color: Default_Theme.accentColor2, size: 20),
                  ),
                ),
              );
            }
            return TipAnchor(
                id: 'T10',
                child: _buildActionIcon(
                    MingCute.download_2_fill,
                    l10n.buttonDownload,
                    isEmpty
                        ? null
                        : () => _handleDownload(context, state, l10n)));
          }),

          const SizedBox(width: 12),

          // Shuffle second, not at the edge: its two bubbles ("Shuffle",
          // "Smart shuffle") open centred above it and need the room.
          TipAnchor(
              id: 'A2',
              child: ShuffleBubbles(
                button: (onTap) => _buildActionIcon(
                    MingCute.shuffle_line, l10n.playlistShuffle, onTap),
                onShuffle: isEmpty
                    ? null
                    : () => _playFromPlaylist(context, state, shuffle: true),
                onSmartShuffle: isEmpty ? null : () => _smartShuffle(context),
              )),
          const SizedBox(width: 12),

          // Big Center Play Button
          StreamBuilder<String>(
              stream:
                  context.watch<BloomeePlayerCubit>().bloomeePlayer.queueTitle,
              builder: (context, snapshot) {
                final isCurrent =
                    snapshot.hasData && snapshot.data == state.playlist.title;
                return StreamBuilder<bool>(
                    stream: context
                        .read<BloomeePlayerCubit>()
                        .bloomeePlayer
                        .engine
                        .playingStream,
                    builder: (context, playingSnapshot) {
                      final isPlaying =
                          isCurrent && (playingSnapshot.data ?? false);
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Default_Theme.accentColor2
                                    .withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: PlayPauseButton(
                          isPlaying: isPlaying,
                          size: 60,
                          onPlay: isEmpty
                              ? () {}
                              : () => isCurrent
                                  ? context
                                      .read<BloomeePlayerCubit>()
                                      .bloomeePlayer
                                      .play()
                                  : _playFromPlaylist(context, state),
                          onPause: () => context
                              .read<BloomeePlayerCubit>()
                              .bloomeePlayer
                              .pause(),
                        ),
                      );
                    });
              }),

          const SizedBox(width: 12),
          // Search where Info was; Info lives in the ⋮ menu now.
          _buildActionIcon(
              _searching ? Icons.close_rounded : MingCute.search_line,
              l10n.playlistSearchHint,
              _toggleSearch),

          const SizedBox(width: 12),
          _buildActionIcon(
              MingCute.more_2_line,
              l10n.buttonMore,
              () => showPlaylistOptsInrSheet(context, state.playlist,
                  onInfo: () => showPlaylistInfo(context, state,
                      fgColor: fgColor, bgColor: bgColor))),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tooltip, VoidCallback? onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(icon,
                color: Colors.white.withValues(alpha: 0.85), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackList(CurrentPlaylistState state) {
    final all = state.playlist.tracks;
    // While searching: only the matches, each keeping its place (number and
    // play position) in the playlist.
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (_matches(all[i])) i
    ];
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, row) {
          final index = shown[row];
          final track = all[index];
          return AnimatedListItem(
            index: row,
            child: SongCardWidget(
              index: index + 1,
              key: ValueKey(track.id),
              song: track,
              onTap: () => _playFromPlaylist(context, state, index: index),
              onOptionsTap: () => showMoreBottomSheet(
                context,
                track,
                onDelete: () => _removeTrack(context, track),
                showDelete: true,
                deleteLabel:
                    AppLocalizations.of(context)!.menuRemoveFromPlaylist,
                showSinglePlay: true,
              ),
            ),
          );
        },
        childCount: shown.length,
        addRepaintBoundaries: true,
      ),
    );
  }

  void _removeTrack(BuildContext context, Track track) {
    final cubit = context.read<CurrentPlaylistCubit>();
    final l10n = AppLocalizations.of(context)!;
    cubit.removeTrack(track);
    SnackbarService.showMessage(
        l10n.playlistRemovedTrack(track.title, cubit.state.playlist.title));
  }

  Future<void> _handleDownload(BuildContext context, CurrentPlaylistState state,
      AppLocalizations l10n) async {
    final items =
        (await context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded())
            .tracks;
    if (items.isEmpty || !context.mounted) return;
    Tips.offer('T11');

    // Only the songs not downloaded (or downloading) yet are asked about and
    // queued; the playlist is recorded either way, so Offline groups it.
    final downloader = context.read<DownloaderCubit>();
    final have = {
      for (final t in downloader.state.downloaded) t.id,
      for (final d in downloader.state.downloads) d.task.song.id,
    };
    final missing = [
      for (final t in items)
        if (!have.contains(t.id)) t
    ];
    if (missing.isEmpty) {
      unawaited(DownloadedPlaylists.add(state.playlist.title, items));
      SnackbarService.showMessage(
          'All ${items.length} songs of "${state.playlist.title}" are downloaded');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Default_Theme.themeColor,
        title: Text(l10n.dialogDownloadPlaylist,
            style: const TextStyle(color: Colors.white)),
        content: Text(
            l10n.dialogDownloadPlaylistMessage(
                missing.length, state.playlist.title),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.buttonCancel,
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.7)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Default_Theme.accentColor2,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.dialogDownloadAll,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Queued in the background, no progress pop-up; the Offline tab shows
      // the playlist and its progress.
      unawaited(DownloadedPlaylists.add(state.playlist.title, items));
      // One batch: no message per song, one at the end; failures show as a
      // banner here with Retry.
      unawaited(downloader.downloadPlaylist(state.playlist.title, missing));
    }
  }
}

/// "2 songs failed to download · Retry", at the top of a playlist whose
/// "Download all" left songs behind. Retry downloads them again, from another
/// source when their own fails.
class _FailedDownloadsBanner extends StatefulWidget {
  const _FailedDownloadsBanner({required this.title});
  final String title;

  @override
  State<_FailedDownloadsBanner> createState() => _FailedDownloadsBannerState();
}

class _FailedDownloadsBannerState extends State<_FailedDownloadsBanner> {
  int _failed = 0;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    DownloadedPlaylists.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DownloadedPlaylists.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final n =
        (await DownloadedPlaylists.loadFailed())[widget.title]?.length ?? 0;
    if (mounted) setState(() => _failed = n);
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final tracks =
        (await context.read<CurrentPlaylistCubit>().ensureAllTracksLoaded())
            .tracks;
    if (!mounted) return;
    await context.read<DownloaderCubit>().retryPlaylist(widget.title, tracks);
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.playlistDownloadFailedBanner(_failed),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _retrying ? null : _retry,
              style: TextButton.styleFrom(
                foregroundColor: Default_Theme.accentColor2,
                backgroundColor:
                    Default_Theme.accentColor2.withValues(alpha: 0.12),
                shape: const StadiumBorder(),
              ),
              child: _retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Default_Theme.accentColor2))
                  : Text(l10n.playlistDownloadRetry,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
