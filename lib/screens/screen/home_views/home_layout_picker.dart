import 'package:Bloomee/core/constants/route_paths.dart';
import 'package:Bloomee/services/tips.dart';
import 'package:go_router/go_router.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/screen/home_views/home_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Lets the user pick a Home layout and saves it. On the first run the
/// sheet cannot be dismissed, and afterwards a dialog says where to change
/// the layout later.
Future<void> showHomeLayoutPicker(BuildContext context,
    {bool firstRun = false}) async {
  final cubit = context.read<SettingsCubit>();
  final picked = await showModalBottomSheet<HomeLayout>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: !firstRun,
    enableDrag: !firstRun,
    backgroundColor: const Color(0xFF121216),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => PopScope(
      canPop: !firstRun,
      child: _LayoutPicker(
          initial: homeLayoutOf(cubit.state.homeLayout), firstRun: firstRun),
    ),
  );
  if (picked == null) return;
  cubit.setHomeLayout(picked.name);
  if (!firstRun || !context.mounted) return;
  await _bringYourMusicThenAllSet(context);
}

/// The end of the first-run flow, on Home: offer to import playlists, then
/// "All set", and from now on the first-time tips can show.
Future<void> _bringYourMusicThenAllSet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final import = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF17171B),
      icon: const Icon(Icons.library_music_rounded,
          color: Default_Theme.accentColor2, size: 36),
      title: const Text('Bring your music',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Default_Theme.primaryColor1)),
      content: Text(
        "Bring your playlists from Spotify. They'll never know you left.",
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 14,
            color: Default_Theme.primaryColor1.withValues(alpha: 0.8)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Later',
              style: TextStyle(
                  color: Default_Theme.primaryColor1.withValues(alpha: 0.7))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Import playlists',
              style: TextStyle(
                  color: Default_Theme.accentColor2,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF17171B),
      icon: const Icon(Icons.check_circle_rounded,
          color: Default_Theme.accentColor2, size: 36),
      title: Text('All set. Volume up, worries down.',
          textAlign: TextAlign.center,
          style: Default_Theme.secondoryTextStyleMedium.merge(const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Default_Theme.primaryColor1))),
      content: Text(
        l10n.homeLayoutChangeLater(l10n.homeLayoutSetting),
        textAlign: TextAlign.center,
        style: Default_Theme.secondoryTextStyle.merge(TextStyle(
            fontSize: 14,
            color: Default_Theme.primaryColor1.withValues(alpha: 0.8))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.homeLayoutGotIt,
              style: const TextStyle(color: Default_Theme.accentColor2)),
        ),
      ],
    ),
  );
  await TipStore.startOver();
  if (import == true && context.mounted) {
    context.pushNamed(RoutePaths.importMediaFromPlatforms);
  }
}

class _LayoutPicker extends StatefulWidget {
  const _LayoutPicker({required this.initial, this.firstRun = false});
  final HomeLayout initial;
  final bool firstRun;

  @override
  State<_LayoutPicker> createState() => _LayoutPickerState();
}

class _LayoutPickerState extends State<_LayoutPicker> {
  late HomeLayout _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = Default_Theme.primaryColor1.withValues(alpha: 0.6);
    final options = {
      HomeLayout.forYou: (l10n.homeLayoutForYou, l10n.homeLayoutForYouDesc),
      HomeLayout.mixes: (l10n.homeLayoutMixes, l10n.homeLayoutMixesDesc),
      HomeLayout.pulse: (l10n.homeLayoutPulse, l10n.homeLayoutPulseDesc),
    };
    // Previews are the mock-ups, named home_layout_a/b/c in enum order.
    const files = {
      HomeLayout.forYou: 'a',
      HomeLayout.mixes: 'b',
      HomeLayout.pulse: 'c',
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.homeLayoutChoose,
                style: Default_Theme.secondoryTextStyleMedium.merge(
                    const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Default_Theme.primaryColor1))),
            const SizedBox(height: 4),
            Text(
                widget.firstRun
                    ? 'Pick a look. You can change it later, unlike that '
                        'haircut in 2019.'
                    : l10n.homeLayoutChooseHint,
                style: Default_Theme.secondoryTextStyle
                    .merge(TextStyle(fontSize: 13, color: muted))),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final layout in HomeLayout.values) ...[
                  if (layout != HomeLayout.values.first)
                    const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = layout),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                width: 2,
                                color: _selected == layout
                                    ? Default_Theme.accentColor2
                                    : const Color(0xFF2A2A31),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: AspectRatio(
                                aspectRatio: 320 / 551,
                                child: Image.asset(
                                  'assets/images/home_layouts/home_layout_${files[layout]}.jpg',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(options[layout]!.$1,
                              style: Default_Theme.secondoryTextStyleMedium
                                  .merge(TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _selected == layout
                                          ? Default_Theme.accentColor2
                                          : Default_Theme.primaryColor1))),
                          Text(options[layout]!.$2,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Default_Theme.secondoryTextStyle.merge(
                                  TextStyle(fontSize: 11, color: muted))),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Default_Theme.accentColor2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context, _selected),
                child: Text(l10n.homeLayoutUse,
                    style: Default_Theme.secondoryTextStyleMedium.merge(
                        const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
