import 'dart:convert';

/// An equalizer curve the user saved under a name.
typedef EqProfile = ({String name, List<double> gains});

/// Profiles saved by [encodeEqProfiles]; empty when [raw] is missing or
/// unreadable.
List<EqProfile> decodeEqProfiles(String? raw) {
  if (raw == null) return const [];
  try {
    return [
      for (final p in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        (
          name: p['name'] as String,
          gains: [for (final g in p['gains'] as List) (g as num).toDouble()],
        )
    ];
  } catch (_) {
    return const [];
  }
}

String encodeEqProfiles(List<EqProfile> profiles) => jsonEncode([
      for (final p in profiles) {'name': p.name, 'gains': p.gains}
    ]);

/// Why [name] cannot be used for a profile, or null when it can. [taken] are
/// the names already in use (built-in presets and other profiles).
String? eqProfileNameError(String name, Iterable<String> taken) {
  final n = name.trim();
  if (n.isEmpty) return 'Enter a name';
  if (n.length > 30) return 'Keep it under 30 characters';
  final lower = n.toLowerCase();
  if (lower == 'custom' || taken.any((t) => t.toLowerCase() == lower)) {
    return 'That name is already used';
  }
  return null;
}
