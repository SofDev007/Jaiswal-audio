import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/services/recommendations/suggestion_blocklist.dart';
import 'package:flutter/material.dart';

/// The minus button on a suggested song: never suggest [track] again, then
/// [onBlocked] (e.g. take it out of the queue). Undo only lifts the block.
class NeverSuggestButton extends StatelessWidget {
  const NeverSuggestButton(
      {super.key, required this.track, this.onBlocked, this.size = 20});
  final Track track;
  final VoidCallback? onBlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: l10n.neverSuggestTooltip,
      iconSize: size,
      splashRadius: 18,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      color: Default_Theme.primaryColor2.withValues(alpha: 0.65),
      icon: const Icon(Icons.remove_circle_outline_rounded),
      onPressed: () async {
        await SuggestionBlocklist.block(track);
        onBlocked?.call();
        SnackbarService.showMessage(
          l10n.neverSuggestDone(track.title),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: l10n.neverSuggestUndo,
            onPressed: () => SuggestionBlocklist.unblock(track),
          ),
        );
      },
    );
  }
}
