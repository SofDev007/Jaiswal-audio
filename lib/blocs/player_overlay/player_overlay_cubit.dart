import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Manages the visibility state of the full-screen player overlay.
class PlayerOverlayCubit extends Cubit<bool> {
  PlayerOverlayCubit() : super(false);

  /// Callback to collapse the UpNext panel, returns true if panel was expanded
  bool Function()? _collapseUpNextPanel;

  /// Register a callback to collapse the UpNext panel
  void registerUpNextPanelCollapse(bool Function() collapse) {
    _collapseUpNextPanel = collapse;
  }

  /// Unregister the UpNext panel collapse callback
  void unregisterUpNextPanelCollapse() {
    _collapseUpNextPanel = null;
  }

  /// Try to collapse the UpNext panel if it's expanded
  /// Returns true if the panel was collapsed, false otherwise
  bool collapseUpNextPanel() {
    return _collapseUpNextPanel?.call() ?? false;
  }

  /// Back press while the player is open: close a screen opened from the
  /// player (those sit on [rootNavigator]), else collapse Up Next, else hide
  /// the player. The page under the player is never popped. Returns false
  /// when the player is closed, so the caller navigates pages instead.
  bool handleBack(NavigatorState rootNavigator) {
    if (!state) return false;
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    } else if (!collapseUpNextPanel()) {
      hidePlayer();
    }
    return true;
  }

  void showPlayer() => emit(true);

  void hidePlayer() => emit(false);

  void togglePlayer() => emit(!state);

  bool get isPlayerVisible => state;
}
