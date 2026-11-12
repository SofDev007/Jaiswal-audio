/// Keys for API tokens and service-level cache entries stored in the database.
/// These replace API/cache-key constants previously mixed into [GlobalStrConsts].
class CacheKeys {
  CacheKeys._();

  // ── LastFM (removed in V2.0; only used to wipe what it stored) ─────────────
  static const String lFMApiKey = "lastFMKey";
  static const String lFMSession = "lastFMSession";
  static const String lFMSecret = "lastFMSecret";
  static const String lFMUsername = "lastFMUsernames";

  /// Cache key for unscrobbled tracks to be submitted on next connection.
  static const String lFMTrackedCache = "lastFMTrackedCacheForFutureScrobble";

  /// Everything Last.fm stored about the user's account.
  static const List<String> lastFmTokens = [
    lFMUsername,
    lFMApiKey,
    lFMSecret,
    lFMSession,
  ];
}
