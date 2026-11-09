part of 'playlist_screen.dart';

class InfoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color fg;
  final Function()? onTap;
  const InfoTile({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.fg = Default_Theme.primaryColor1,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      title: Text(
        title,
        style: Default_Theme.secondoryTextStyle.merge(
          TextStyle(
              color: fg.withValues(alpha: 0.5),
              fontSize: 13,
              fontFamily: 'Unageo'),
        ),
      ),
      hoverColor: Colors.transparent,
      selectedColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      subtitle: SelectableText(
        subtitle,
        style: Default_Theme.secondoryTextStyle.merge(
          TextStyle(color: fg, fontSize: 15, fontFamily: 'NotoSans'),
        ),
      ),
      leading: Icon(
        icon,
        size: 20,
        color: fg,
      ),
    );
  }
}

/// Total length of [tracks] like Spotify: "4h 36min", "45 min". Null when
/// no song has a known length.
String? playlistLength(List<Track> tracks) {
  var ms = 0;
  for (final t in tracks) {
    ms += t.durationMs?.toInt() ?? 0;
  }
  if (ms <= 0) return null;
  final d = Duration(milliseconds: ms);
  if (d.inHours == 0) return '${d.inMinutes.clamp(1, 59)} min';
  return '${d.inHours}h ${d.inMinutes % 60}min';
}

/// "28/10/2026 at 3:08 AM" (DD/MM/YYYY) in the phone's time zone.
String _readableDate(DateTime t) =>
    DateFormat("dd/MM/yyyy 'at' h:mm a").format(t.toLocal());

Future<dynamic> showPlaylistInfo(
  BuildContext context,
  CurrentPlaylistState state, {
  Color bgColor = const Color.fromARGB(255, 15, 0, 19),
  Color fgColor = Default_Theme.primaryColor1,
}) {
  bgColor =
      bgColor == Colors.black ? const Color.fromARGB(255, 15, 0, 19) : bgColor;
  fgColor = fgColor == Colors.white ? Default_Theme.primaryColor1 : fgColor;
  return showDialog(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      return Dialog(
          backgroundColor: bgColor,
          shadowColor: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        state.playlist.title,
                        style: Default_Theme.secondoryTextStyle.merge(
                          TextStyle(
                              color: fgColor,
                              fontSize: 16,
                              fontFamily: 'NotoSans',
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // When it was made. "Created by" (the account's name) is
                    // added with V2's Google login, which knows who is using
                    // JARX.
                    if (state.playlist.createdAt != null)
                      InfoTile(
                        title: l10n.playlistInfoCreated,
                        subtitle: _readableDate(state.playlist.createdAt!),
                        icon: MingCute.calendar_line,
                        fg: fgColor,
                      ),
                    state.playlist.description != null
                        ? InfoTile(
                            title: "Description",
                            subtitle: state.playlist.description!,
                            icon: MingCute.document_2_line,
                            fg: fgColor,
                          )
                        : const SizedBox.shrink(),
                    state.playlist.updatedAt != null
                        ? InfoTile(
                            title: l10n.playlistInfoUpdated,
                            subtitle: _readableDate(state.playlist.updatedAt!),
                            icon: MingCute.history_line,
                            fg: fgColor,
                          )
                        : const SizedBox.shrink(),
                    state.playlist.permaURL != null
                        ? InfoTile(
                            title: "Original URL",
                            subtitle: state.playlist.permaURL!,
                            icon: MingCute.external_link_line,
                            fg: fgColor,
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text: state.playlist.permaURL!));
                              SnackbarService.showMessage(
                                  "URL Copied to Clipboard");
                            },
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ));
    },
  );
}
