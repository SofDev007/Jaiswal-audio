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
      child: _LayoutPicker(initial: homeLayoutOf(cubit.state.homeLayout)),
    ),
  );
  if (picked == null) return;
  cubit.setHomeLayout(picked.name);
  if (!firstRun || !context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF17171B),
      icon: const Icon(Icons.check_circle_rounded,
          color: Default_Theme.accentColor2, size: 36),
      title: Text(l10n.homeLayoutDoneTitle,
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
}

class _LayoutPicker extends StatefulWidget {
  const _LayoutPicker({required this.initial});
  final HomeLayout initial;

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
            Text(l10n.homeLayoutChooseHint,
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
