import 'package:Bloomee/screens/widgets/tip_overlay.dart';
import 'package:Bloomee/core/constants/quips.dart';
import 'package:Bloomee/blocs/internet_connectivity/cubit/connectivity_cubit.dart';
import 'package:Bloomee/blocs/notification/notification_cubit.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/blocs/content/content_bloc.dart';
import 'package:Bloomee/plugins/blocs/content/content_event.dart';
import 'package:Bloomee/plugins/blocs/content/content_state.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_state.dart';
import 'package:Bloomee/screens/widgets/sign_board_widget.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/screens/widgets/skeleton.dart';
import 'package:Bloomee/screens/screen/home_views/home_layout_picker.dart';
import 'package:Bloomee/screens/screen/home_views/home_rows.dart';
import 'package:Bloomee/screens/screen/home_views/notification_view.dart';
import 'package:Bloomee/screens/screen/home_views/setting_view.dart';
import 'package:Bloomee/screens/screen/home_views/your_corner_view.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:icons_plus/icons_plus.dart';
import '../widgets/horizontal_card_view.dart';
import 'package:badges/badges.dart' as badges;
import 'package:Bloomee/screens/widgets/update_tour.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  bool isUpdateChecked = false;
  late final ContentBloc _homeContentBloc;

  @override
  void initState() {
    super.initState();
    _homeContentBloc = ContentBloc(pluginService: ServiceLocator.pluginService);
    _tryLoadHomeSections();
    _maybeAskLayout();
  }

  bool _layoutAsked = false;

  /// First run: once settings are loaded and no Home layout is saved yet,
  /// ask the user to pick one.
  void _maybeAskLayout() {
    final settings = context.read<SettingsCubit>().state;
    if (_layoutAsked || !settings.settingsReady || settings.homeLayout != '') {
      return;
    }
    _layoutAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showHomeLayoutPicker(context, firstRun: true);
    });
  }

  /// Only loads home sections when both settings are ready and plugins are loaded.
  void _tryLoadHomeSections() {
    final settingsState = context.read<SettingsCubit>().state;
    if (!settingsState.settingsReady) return;

    final pluginState = context.read<PluginBloc>().state;
    final contentResolvers = pluginState.loadedContentResolvers;
    if (contentResolvers.isEmpty) return;

    final preferredId = settingsState.homePluginId;
    // If the user's preferred plugin is installed but not yet loaded, wait for it.
    // This prevents flashing the wrong plugin's home page on startup.
    if (preferredId.isNotEmpty) {
      final isAlreadyLoaded =
          contentResolvers.any((p) => p.manifest.id == preferredId);
      if (!isAlreadyLoaded) {
        final isInstalled = pluginState.availablePlugins
            .any((p) => p.manifest.id == preferredId);
        if (isInstalled) return; // Preferred plugin is loading — wait for it
      }
    }

    final pluginId = _effectiveHomePluginId(contentResolvers);

    // Don't reload if we're already showing content from this plugin.
    if (_homeContentBloc.state.activePluginId == pluginId &&
        _homeContentBloc.state.homeSections != null) {
      return;
    }

    _homeContentBloc.add(GetHomeSections(pluginId: pluginId));
  }

  String _effectiveHomePluginId(List<dynamic> loadedResolvers) {
    final preferredId = context.read<SettingsCubit>().state.homePluginId;
    final hasPreferred = preferredId.isNotEmpty &&
        loadedResolvers.any((plugin) => plugin.manifest.id == preferredId);
    return hasPreferred ? preferredId : loadedResolvers.first.manifest.id;
  }

  @override
  void dispose() {
    _homeContentBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MultiBlocListener(
        listeners: [
          BlocListener<SettingsCubit, SettingsState>(
            listenWhen: (previous, current) =>
                previous.homePluginId != current.homePluginId ||
                (!previous.settingsReady && current.settingsReady),
            listener: (context, state) {
              _homeContentBloc.add(const ClearHomeSections());
              _tryLoadHomeSections();
              _maybeAskLayout();
            },
          ),
          BlocListener<PluginBloc, PluginState>(
            listenWhen: (previous, current) {
              return previous.loadedContentResolvers !=
                      current.loadedContentResolvers ||
                  previous.loadedPluginIds != current.loadedPluginIds;
            },
            listener: (context, state) {
              if (state.loadedContentResolvers.isEmpty) {
                _homeContentBloc.add(const ClearHomeSections());
                return;
              }

              final activePluginId = _homeContentBloc.state.activePluginId;
              if (activePluginId != null &&
                  !state.loadedPluginIds.contains(activePluginId)) {
                // Active plugin was unloaded — reload from preferred.
                _homeContentBloc.add(const ClearHomeSections());
                _tryLoadHomeSections();
                return;
              }

              // Plugin list changed — check if preferred plugin is different.
              _tryLoadHomeSections();
            },
          ),
        ],
        child: Scaffold(
          body: RefreshIndicator(
            color: Default_Theme.accentColor2,
            backgroundColor: Default_Theme.themeColor,
            strokeWidth: 2.5,
            displacement: 56,
            onRefresh: () async {
              final pluginId = _effectiveHomePluginId(
                context.read<PluginBloc>().state.loadedContentResolvers,
              );
              _homeContentBloc.add(
                GetHomeSections(pluginId: pluginId, bypassCache: true),
              );
            },
            child: CustomScrollView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              slivers: [
                const CustomDiscoverBar(),
                SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      BlocBuilder<SettingsCubit, SettingsState>(
                        buildWhen: (a, b) => a.homeLayout != b.homeLayout,
                        builder: (context, settings) =>
                            BlocBuilder<ContentBloc, ContentState>(
                          bloc: _homeContentBloc,
                          buildWhen: (a, b) =>
                              a.homeSectionsStatus != b.homeSectionsStatus,
                          builder: (context, state) => HomeTop(
                            layout: homeLayoutOf(settings.homeLayout),
                            // For you starts after the Home sections, so it
                            // does not queue ahead of them (or a search) on
                            // the same plugin.
                            homeReady: state.homeSectionsStatus ==
                                    DetailStatus.loaded ||
                                state.homeSectionsStatus == DetailStatus.error,
                          ),
                        ),
                      ),
                      // Home sections from plugin
                      BlocBuilder<ContentBloc, ContentState>(
                        bloc: _homeContentBloc,
                        builder: (context, state) {
                          final loadedResolvers = context
                              .read<PluginBloc>()
                              .state
                              .loadedContentResolvers;
                          if (loadedResolvers.isEmpty) {
                            return const SignBoardWidget(
                              message:
                                  'No content plugin loaded.\nLoad a Content Resolver in Plugin Manager.',
                              icon: MingCute.plugin_2_line,
                            );
                          }

                          final sections = state.homeSections ?? const [];
                          final hasSections = sections.isNotEmpty;
                          final activePluginId = state.activePluginId;
                          if (activePluginId != null &&
                              !context
                                  .read<PluginBloc>()
                                  .state
                                  .loadedPluginIds
                                  .contains(activePluginId) &&
                              !hasSections) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: SignBoardWidget(
                                message:
                                    'Refreshing Discover source...\nThe previous source is no longer available.',
                                icon: MingCute.warning_line,
                              ),
                            );
                          }

                          if (state.homeSectionsStatus ==
                              DetailStatus.loading) {
                            if (hasSections) {
                              return _HomeSectionsList(
                                sections: sections,
                                contentBloc: _homeContentBloc,
                                state: state,
                              );
                            }

                            return BlocBuilder<ConnectivityCubit,
                                ConnectivityState>(
                              builder: (context, connState) {
                                if (connState ==
                                    ConnectivityState.disconnected) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: SignBoardWidget(
                                      message: noInternetQuip,
                                      icon: MingCute.wifi_off_line,
                                    ),
                                  );
                                }

                                return const SkeletonCardRows();
                              },
                            );
                          }

                          if (state.homeSectionsStatus == DetailStatus.error) {
                            if (hasSections) {
                              return _HomeSectionsList(
                                sections: sections,
                                contentBloc: _homeContentBloc,
                                state: state,
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: SignBoardWidget(
                                message: state.error ??
                                    'Failed to load home sections.',
                                icon: MingCute.sweats_line,
                              ),
                            );
                          }

                          if (!hasSections) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SizedBox.shrink(),
                            );
                          }

                          return _HomeSectionsList(
                            sections: sections,
                            contentBloc: _homeContentBloc,
                            state: state,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Default_Theme.themeColor,
        ),
      ),
    );
  }
}

class _HomeSectionsList extends StatelessWidget {
  final List<Section> sections;
  final ContentBloc contentBloc;
  final ContentState state;

  const _HomeSectionsList({
    required this.sections,
    required this.contentBloc,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemExtent: 275,
      padding: const EdgeInsets.only(top: 0),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return HorizontalCardView(
          section: section,
          pluginId: contentBloc.state.activePluginId ?? '',
          canLoadMore: section.moreLink != null,
          isLoadingMore: state.isHomeSectionLoading(section.id),
          onLoadMore: section.moreLink == null
              ? null
              : () {
                  contentBloc.add(
                    LoadMoreHomeSectionItems(
                      pluginId: contentBloc.state.activePluginId ?? '',
                      sectionId: section.id,
                      moreLink: section.moreLink!,
                    ),
                  );
                },
        );
      },
    );
  }
}

class CustomDiscoverBar extends StatelessWidget {
  const CustomDiscoverBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (a, b) => a.homeLayout != b.homeLayout,
      builder: (context, state) => SliverAppBar(
        floating: true,
        surfaceTintColor: Default_Theme.themeColor,
        backgroundColor: Default_Theme.themeColor,
        title: Row(
          children: [
            Expanded(
                child: homeLayoutOf(state.homeLayout) == HomeLayout.forYou
                    ? const HomeGreeting()
                    : const HomeTitle()),
            const NotificationIcon(),
            const ProfileButton(),
            const SettingsIcon(),
          ],
        ),
      ),
    );
  }
}

class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key});

  @override
  Widget build(BuildContext context) {
    // Keyed so the compulsory-update tour can put its spotlight here.
    return KeyedSubtree(
        key: updateBellKey,
        child: BlocBuilder<NotificationCubit, NotificationState>(
          builder: (context, state) {
            if (state is NotificationInitial || state.notifications.isEmpty) {
              return IconButton(
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationView(),
                    ),
                  );
                },
                icon: const Icon(
                  MingCute.notification_line,
                  color: Default_Theme.primaryColor1,
                  size: 30.0,
                ),
              );
            }
            return TipAnchor(
                id: 'T16',
                child: badges.Badge(
                  badgeContent: Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: Text(
                      state.notifications.length.toString(),
                      style: Default_Theme.primaryTextStyle.merge(
                        const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Default_Theme.primaryColor2,
                        ),
                      ),
                    ),
                  ),
                  badgeStyle: const badges.BadgeStyle(
                    badgeColor: Default_Theme.accentColor2,
                    shape: badges.BadgeShape.circle,
                  ),
                  position: badges.BadgePosition.topEnd(top: -10, end: -5),
                  child: IconButton(
                    padding: const EdgeInsets.all(5),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationView(),
                        ),
                      );
                    },
                    icon: const Icon(
                      MingCute.notification_line,
                      color: Default_Theme.primaryColor1,
                      size: 30.0,
                    ),
                  ),
                ));
          },
        ));
  }
}

/// The user's Google photo (or initial): opens Your corner. It took the
/// sleep timer's place; the timer lives in the player.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TipAnchor(
      id: 'T14',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const YourCornerView())),
          child: const UserAvatar(size: 30),
        ),
      ),
    );
  }
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsView()),
        );
      },
      icon: const Icon(
        MingCute.settings_3_line,
        color: Default_Theme.primaryColor1,
        size: 30.0,
      ),
    );
  }
}
