import 'dart:developer';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/screens/widgets/downloading_item.dart';
import 'package:Bloomee/screens/widgets/more_bottom_sheet.dart';
import 'package:Bloomee/screens/widgets/sign_board_widget.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/screens/widgets/song_tile.dart';
import 'package:Bloomee/services/downloaded_playlists.dart';
import 'package:Bloomee/utils/load_image.dart';
import 'package:Bloomee/utils/download_types.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:icons_plus/icons_plus.dart';

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _isSearch = false;
  final TextEditingController _searchController = TextEditingController();
  List<Track> _filteredSongs = [];
  List<({String title, List<String> ids})> _savedPlaylists = const [];

  @override
  void initState() {
    super.initState();
    final downloaderState = context.read<DownloaderCubit>().state;
    _filteredSongs = downloaderState.downloaded;
    _searchController.addListener(_filterSongs);
    _loadSavedPlaylists();
    DownloadedPlaylists.changes.addListener(_loadSavedPlaylists);
  }

  Future<void> _loadSavedPlaylists() async {
    final saved = await DownloadedPlaylists.load();
    if (mounted) setState(() => _savedPlaylists = saved);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterSongs);
    DownloadedPlaylists.changes.removeListener(_loadSavedPlaylists);
    _searchController.dispose();
    super.dispose();
  }

  void _filterSongs() {
    final downloaderState = context.read<DownloaderCubit>().state;
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSongs = downloaderState.downloaded
          .where((song) =>
              "${song.title.toLowerCase()} ${song.artists.map((a) => a.name).join(', ').toLowerCase()}"
                  .contains(query))
          .toList();
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearch = !_isSearch;
      // When closing the search, clear the controller and reset the filter
      if (!_isSearch) {
        _searchController.clear();
        final downloaderState = context.read<DownloaderCubit>().state;
        _filteredSongs = downloaderState.downloaded;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Scaffold(
        backgroundColor: Default_Theme.themeColor,
        body: BlocConsumer<DownloaderCubit, DownloaderState>(
          listenWhen: (a, b) => a.downloaded.length != b.downloaded.length,
          listener: (_, __) => _loadSavedPlaylists(),
          builder: (context, state) {
            // Not searching: downloaded playlists as cards, then the songs
            // downloaded one by one.
            final grouped = _searchController.text.isEmpty
                ? DownloadedPlaylists.group(state.downloaded, _savedPlaylists)
                : null;
            if (grouped != null) _filteredSongs = grouped.singles;
            return CustomScrollView(
              slivers: [
                customDiscoverSliverBar(context, l10n),
                if (state.downloaded.isEmpty &&
                    !context.read<DownloaderCubit>().initialLoadDone)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Default_Theme.accentColor2),
                    ),
                  )
                else if (state.downloads.isEmpty && state.downloaded.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: SignBoardWidget(
                        message: l10n.offlineNoDownloads,
                        icon: FontAwesome.download_solid,
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        if (state.downloads.isNotEmpty)
                          _DownloadsHeader(
                              showPause: state.downloads.any((d) =>
                                  d.status.state != DownloadState.failed),
                              running:
                                  context.read<DownloaderCubit>().anyRunning),
                        ..._activeDownloads(context, state),
                        for (final p in grouped?.playlists ?? const [])
                          _DownloadedPlaylistTile(
                            title: p.title,
                            tracks: p.tracks,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _DownloadedPlaylistView(
                                    title: p.title, tracks: p.tracks),
                              ),
                            ),
                          ),
                        ..._filteredSongs.map((song) => SongCardWidget(
                              song: song,
                              showOptions: true,
                              delDownBtn: true,
                              onTap: () {
                                final selectedIndex =
                                    state.downloaded.indexWhere(
                                  (item) => item.id == song.id,
                                );

                                if (selectedIndex < 0 ||
                                    state.downloaded.isEmpty) {
                                  SnackbarService.showMessage(
                                      l10n.offlineOpenFailed);
                                  log(
                                    'Offline play failed: missing track in downloaded list (${song.id})',
                                    name: 'OfflineScreen',
                                  );
                                  return;
                                }

                                try {
                                  context
                                      .read<BloomeePlayerCubit>()
                                      .bloomeePlayer
                                      .loadPlaylist(
                                        Playlist(
                                          tracks: state.downloaded,
                                          title: "Offline",
                                        ),
                                        idx: selectedIndex,
                                        doPlay: true,
                                      );
                                } catch (e, stack) {
                                  log(
                                    'Offline play crashed for ${song.id}',
                                    name: 'OfflineScreen',
                                    error: e,
                                    stackTrace: stack,
                                  );
                                  SnackbarService.showMessage(
                                      l10n.offlinePlayFailed);
                                }
                              },
                              onOptionsTap: () {
                                showMoreBottomSheet(context, song,
                                    showDelete: false);
                              },
                            )),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Downloads in progress: one card per "Download all" playlist (its
  /// songs inside), then songs downloaded one by one.
  List<Widget> _activeDownloads(BuildContext context, DownloaderState state) {
    final cubit = context.read<DownloaderCubit>();
    final groups = groupActiveDownloads<DownloadProgress>(state.downloads,
        (d) => cubit.originalIdOf(d.task.mediaId), _savedPlaylists);
    final have = {for (final t in state.downloaded) t.id};
    return [
      for (final p in groups.playlists)
        _DownloadingPlaylistCard(
          key: ValueKey('dl-${p.title}'),
          title: p.title,
          total: p.ids.length,
          done: p.ids.where(have.contains).length,
          rows: p.rows,
        ),
      ...groups.singles.map((d) => DownloadingCardWidget(downloadProgress: d)),
    ];
  }

  SliverAppBar customDiscoverSliverBar(
      BuildContext context, AppLocalizations l10n) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      surfaceTintColor: Default_Theme.themeColor,
      backgroundColor: Default_Theme.themeColor,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (Widget child, Animation<double> animation) {
          final slideAnimation = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slideAnimation,
              child: child,
            ),
          );
        },
        child: _isSearch ? _buildSearchField(l10n) : _buildTitle(l10n),
      ),
      actions: [
        !_isSearch
            ? Tooltip(
                message: l10n.offlineRefreshTooltip,
                child: IconButton(
                  icon: const Icon(MingCute.refresh_2_line),
                  onPressed: () {
                    context.read<DownloaderCubit>().refreshDownloadedSongs();
                  },
                ),
              )
            : const SizedBox.shrink(),
        Tooltip(
          message:
              _isSearch ? l10n.offlineCloseSearch : l10n.offlineSearchTooltip,
          child: IconButton(
            icon: Icon(
              _isSearch ? Icons.close : Icons.search,
              color: Default_Theme.primaryColor1,
            ),
            onPressed: _toggleSearch,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(AppLocalizations l10n) {
    return Container(
      key: const ValueKey('title'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.offlineTitle,
              style: Default_Theme.primaryTextStyle.merge(const TextStyle(
                  fontSize: 34, color: Default_Theme.primaryColor1))),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return Container(
      key: const ValueKey('search'),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        cursorColor: Default_Theme.primaryColor1,
        decoration: InputDecoration(
          hintText: l10n.offlineSearchHint,
          border: InputBorder.none,
          hintStyle: TextStyle(
              color: Default_Theme.primaryColor1.withValues(alpha: 0.7)),
        ),
        style: Default_Theme.secondoryTextStyle.merge(
          const TextStyle(
            color: Default_Theme.primaryColor1,
            fontSize: 15.0,
          ),
        ),
      ),
    );
  }
}

/// A playlist downloaded with "Download all", as one row in Offline.
class _DownloadedPlaylistTile extends StatelessWidget {
  const _DownloadedPlaylistTile(
      {required this.title, required this.tracks, required this.onTap});
  final String title;
  final List<Track> tracks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LoadImageCached(
            imageUrl: tracks.first.thumbnail.url,
            width: 56,
            height: 56,
          ),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Default_Theme.primaryColor1,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} downloaded',
            style: TextStyle(
                color: Default_Theme.primaryColor2.withValues(alpha: 0.7))),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Default_Theme.primaryColor2),
      );
}

/// The downloaded songs of one playlist; playing one plays the playlist.
class _DownloadedPlaylistView extends StatelessWidget {
  const _DownloadedPlaylistView({required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Default_Theme.themeColor,
        appBar: AppBar(
          backgroundColor: Default_Theme.themeColor,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Default_Theme.primaryColor1),
          title: Text(title,
              style: const TextStyle(
                  color: Default_Theme.primaryColor1,
                  fontWeight: FontWeight.w700)),
        ),
        body: ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) => SongCardWidget(
            song: tracks[i],
            showOptions: true,
            delDownBtn: true,
            onTap: () => context
                .read<BloomeePlayerCubit>()
                .bloomeePlayer
                .loadPlaylist(Playlist(tracks: tracks, title: title),
                    idx: i, doPlay: true),
            onOptionsTap: () =>
                showMoreBottomSheet(context, tracks[i], showDelete: false),
          ),
        ),
      );
}

/// Splits [rows] (active downloads) into the "Download all" playlists in
/// [saved] they belong to, in [saved] order, and the songs downloaded one by
/// one. [idOf] gives a row's song id; playlists with nothing downloading
/// are left out, and a song is shown once, in the first playlist it is in.
({
  List<({String title, List<String> ids, List<T> rows})> playlists,
  List<T> singles,
}) groupActiveDownloads<T>(List<T> rows, String Function(T) idOf,
    List<({String title, List<String> ids})> saved) {
  final left = List.of(rows);
  final playlists = <({String title, List<String> ids, List<T> rows})>[];
  for (final p in saved) {
    final ids = p.ids.toSet();
    final mine = left.where((r) => ids.contains(idOf(r))).toList();
    if (mine.isEmpty) continue;
    left.removeWhere(mine.contains);
    playlists.add((title: p.title, ids: p.ids, rows: mine));
  }
  return (playlists: playlists, singles: left);
}

/// Above the downloads: "Pause all" / "Resume all" and "Cancel all".
class _DownloadsHeader extends StatelessWidget {
  const _DownloadsHeader({required this.showPause, required this.running});
  final bool showPause, running;

  Future<void> _confirmCancelAll(BuildContext context) async {
    final cubit = context.read<DownloaderCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Default_Theme.themeColor,
        title: const Text('Cancel all downloads?',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Text('Songs already downloaded stay on your phone.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep downloading',
                  style: TextStyle(color: Default_Theme.primaryColor1))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel all',
                  style: TextStyle(
                      color: Default_Theme.accentColor2,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok == true) await cubit.cancelAll();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<DownloaderCubit>();
    ButtonStyle style(Color c) => TextButton.styleFrom(
          foregroundColor: c,
          backgroundColor: c.withValues(alpha: 0.12),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
      child: Row(
        children: [
          const Text('Downloading',
              style: TextStyle(
                  color: Default_Theme.primaryColor1,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (showPause)
            TextButton.icon(
              onPressed: running ? cubit.pauseAll : cubit.resumeAll,
              style: style(Default_Theme.accentColor2),
              icon: Icon(
                  running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 18),
              label: Text(
                  running ? l10n.offlinePauseAll : l10n.offlineResumeAll,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _confirmCancelAll(context),
            style: style(Default_Theme.primaryColor1),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel all',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// A playlist being downloaded with "Download all", as one card: how many
/// of its songs are downloaded and what the rest are doing. Tap to see its
/// songs (each with its own pause / cancel / retry).
class _DownloadingPlaylistCard extends StatefulWidget {
  const _DownloadingPlaylistCard({
    super.key,
    required this.title,
    required this.total,
    required this.done,
    required this.rows,
  });
  final String title;
  final int total, done;
  final List<DownloadProgress> rows;

  @override
  State<_DownloadingPlaylistCard> createState() =>
      _DownloadingPlaylistCardState();
}

class _DownloadingPlaylistCardState extends State<_DownloadingPlaylistCard> {
  bool _open = false;

  String _summary(DownloaderCubit cubit) {
    var downloading = 0, waiting = 0, wifi = 0, paused = 0, failed = 0;
    for (final d in widget.rows) {
      if (cubit.isWaitingForWifi(d.task.taskId)) {
        wifi++;
        continue;
      }
      switch (d.status.state) {
        case DownloadState.queued:
          waiting++;
        case DownloadState.paused:
          paused++;
        case DownloadState.failed:
          failed++;
        case DownloadState.completed:
        case DownloadState.cancelled:
          break;
        default:
          downloading++;
      }
    }
    return [
      if (downloading > 0) '$downloading downloading',
      if (waiting > 0) '$waiting waiting',
      if (wifi > 0) '$wifi waiting for Wi-Fi',
      if (paused > 0) '$paused paused',
      if (failed > 0) '$failed failed',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DownloaderCubit>();
    final song = widget.rows.first.task.song;
    final share = widget.total == 0 ? 0.0 : widget.done / widget.total;
    final dim = Default_Theme.primaryColor2.withValues(alpha: 0.7);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LoadImageCached(
                    imageUrl: song.thumbnail.urlLow ?? song.thumbnail.url,
                    width: 55,
                    height: 55,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Default_Theme.primaryColor1,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${widget.done} of ${widget.total} downloaded',
                          style: TextStyle(color: dim, fontSize: 12.5)),
                      Text(_summary(cubit),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: dim, fontSize: 12)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: share),
                          duration: const Duration(milliseconds: 400),
                          builder: (_, v, __) => LinearProgressIndicator(
                            value: v,
                            minHeight: 4,
                            backgroundColor: Default_Theme.primaryColor2
                                .withValues(alpha: 0.15),
                            color: Default_Theme.accentColor2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.expand_more_rounded,
                      color: Default_Theme.primaryColor2),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(children: [
                    for (final d in widget.rows)
                      DownloadingCardWidget(downloadProgress: d),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
