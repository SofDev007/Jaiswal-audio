/// Names to show for plugins whose own name is misspelt, by plugin ID. The ID
/// and the plugin's own name belong to its author and must stay as they are
/// (installs and updates match on the ID).
const _displayNames = {
  'content-resolver.bloomfactory.jisaavn': 'JioSaavn',
};

/// The name to show for the plugin with [id] whose own name is [name].
String pluginDisplayName(String id, String name) => _displayNames[id] ?? name;
