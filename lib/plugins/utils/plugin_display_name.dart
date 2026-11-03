/// Names to show for plugins whose own name is misspelt, by plugin ID. The ID
/// and the plugin's own name belong to its author and must stay as they are
/// (installs and updates match on the ID).
const _displayNames = {
  'content-resolver.bloomfactory.jisaavn': 'JioSaavn',
};

/// The name to show for the plugin with [id] whose own name is [name].
String pluginDisplayName(String id, String name) => _displayNames[id] ?? name;

/// Where a song comes from, for "Enjoying From …" when it wasn't started from
/// a playlist: "YouTube Music", "JioSaavn", "YouTube Video", or "Local".
String sourceNameOfTrack(String trackId) {
  final plugin = trackId.split('::').first;
  return const {
        'content-resolver.bloomfactory.ytmusic': 'YouTube Music',
        'content-resolver.bloomfactory.ytvideo': 'YouTube Video',
        'content-resolver.bloomfactory.jisaavn': 'JioSaavn',
      }[plugin] ??
      (trackId.contains('::') ? 'Search' : 'Local');
}
