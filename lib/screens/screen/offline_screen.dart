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
                        ...state.downloads.map((download) =>
                            DownloadingCardWidget(downloadProgress: download)),
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
