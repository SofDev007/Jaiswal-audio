/// Key for comparing artist names across plugins: lowercase, single spaces.
String artistKeyOf(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// A user skip counts as "early" in the first 30 s and before 25% of the
/// track (when its length is known).
bool isEarlySkip(Duration position, int? durationMs) =>
    position < const Duration(seconds: 30) &&
    (durationMs == null ||
        durationMs <= 0 ||
        position.inMilliseconds < durationMs * 0.25);

/// What the user has done with one track, aggregated on the device.
class TrackSignal {
  final String mediaId;

  /// Normalized primary artist name.
  final String artistKey;

  /// Primary artist as shown.
  final String artistName;
  final int plays;
  final int completions;

  /// User skips in the first 30 s and before 25% of the track.
  final int earlySkips;
  final DateTime? lastPlayedAt;

  const TrackSignal({
    required this.mediaId,
    required this.artistKey,
    required this.artistName,
    this.plays = 0,
    this.completions = 0,
    this.earlySkips = 0,
    this.lastPlayedAt,
  });
}
