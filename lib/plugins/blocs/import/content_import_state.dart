import 'package:equatable/equatable.dart';

import 'package:Bloomee/services/csv_playlist_parser.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';

/// A match at or above this confidence is shown as matched; below it (but
/// above the resolver's floor) it is shown as needing a check.
const double kConfidentMatch = 0.75;

enum ImportPhase {
  idle,
  checkingUrl,
  fetchingInfo,
  fetchingTracks,
  resolving,
  review,
  saving,
  done,
  error,
}

/// Why an import failed, so the UI can say what happened and what to do.
enum ImportErrorKind {
  unsupportedUrl,

  /// Private, deleted or region-locked.
  notFound,
  emptyCollection,
  authFailed,
  rateLimited,
  network,
  timeout,

  /// An earlier call the app gave up on is still running in the plugin.
  pluginBusy,
  pluginUnavailable,

  /// No content-resolver plugin is loaded to match tracks against.
  noResolvers,

  /// Matching stopped on an unexpected error; the parsed tracks are kept.
  matchingFailed,
  unexpectedResponse,
  saveFailed,
  unknown;

  /// Worth retrying automatically after a short wait.
  bool get isTransient => this == network || this == rateLimited;
}

/// Resolution status of a single track during import.
enum TrackResolutionStatus {
  pending,
  resolving,
  resolved,
  failed,

  /// The lookup itself failed (not "no match"); matching again retries it.
  error,
}

/// How an entry looks in review.
enum ImportMatchState {
  pending,

  /// Auto-matched at or above [kConfidentMatch].
  matched,

  /// Auto-matched below [kConfidentMatch]: may be a different song.
  uncertain,

  /// The user picked this candidate.
  userSelected,
  unmatched,
  skipped,
}

/// A track from the import source paired with its resolution state.
class ImportTrackEntry extends Equatable {
  final ImportTrackItem sourceTrack;
  final TrackResolutionStatus status;

  /// Best auto-resolved track (first candidate found).
  final Track? resolvedTrack;

  /// Up to 5 candidate tracks from search results.
  final List<Track> candidates;

  /// Confidence (0–1) of each of [candidates], same order.
  final List<double> confidences;

  /// User-selected candidate index.
  /// - null  → use [resolvedTrack] (auto best)
  /// - >= 0  → use [candidates[selectedCandidateIndex]]
  /// - -1    → user explicitly skipped this track
  final int? selectedCandidateIndex;

  const ImportTrackEntry({
    required this.sourceTrack,
    this.status = TrackResolutionStatus.pending,
    this.resolvedTrack,
    this.candidates = const [],
    this.confidences = const [],
    this.selectedCandidateIndex,
  });

  /// Whether the user has explicitly chosen to skip this track.
  bool get isSkipped => selectedCandidateIndex == -1;

  /// The track that will be saved (respects user selection / skip).
  Track? get effectiveTrack {
    if (isSkipped) return null;
    final idx = selectedCandidateIndex;
    if (idx != null && idx >= 0 && idx < candidates.length) {
      return candidates[idx];
    }
    return resolvedTrack;
  }

  /// Confidence of [effectiveTrack], when it came from scoring.
  double? get confidence {
    if (isSkipped) return null;
    final idx = selectedCandidateIndex ??
        (resolvedTrack != null && candidates.isNotEmpty ? 0 : null);
    if (idx == null || idx < 0 || idx >= confidences.length) return null;
    return confidences[idx];
  }

  ImportMatchState get matchState {
    if (isSkipped) return ImportMatchState.skipped;
    if (status == TrackResolutionStatus.pending ||
        status == TrackResolutionStatus.resolving) {
      return ImportMatchState.pending;
    }
    if (effectiveTrack == null) return ImportMatchState.unmatched;
    if (selectedCandidateIndex != null) return ImportMatchState.userSelected;
    return (confidence ?? 0) >= kConfidentMatch
        ? ImportMatchState.matched
        : ImportMatchState.uncertain;
  }

  ImportTrackEntry copyWith({
    TrackResolutionStatus? status,
    Track? resolvedTrack,
    List<Track>? candidates,
    List<double>? confidences,
    int? selectedCandidateIndex,
    bool clearSelection = false,
  }) {
    return ImportTrackEntry(
      sourceTrack: sourceTrack,
      status: status ?? this.status,
      resolvedTrack: resolvedTrack ?? this.resolvedTrack,
      candidates: candidates ?? this.candidates,
      confidences: confidences ?? this.confidences,
      selectedCandidateIndex: clearSelection
          ? null
          : (selectedCandidateIndex ?? this.selectedCandidateIndex),
    );
  }

  @override
  List<Object?> get props => [
        sourceTrack,
        status,
        resolvedTrack,
        candidates,
        confidences,
        selectedCandidateIndex,
      ];
}

class ContentImportState extends Equatable {
  final ImportPhase phase;
  final String? pluginId;
  final String? url;
  final ImportCollectionSummary? collectionInfo;
  final List<ImportTrackEntry> tracks;
  final int resolvedCount;
  final int failedCount;
  final String? error;
  final ImportErrorKind? errorKind;

  /// 1 for the first try of the current step, higher while retrying it.
  final int attempt;

  /// When the current step started, for showing elapsed time.
  final DateTime? phaseStartedAt;

  /// File rows left out of [tracks] (malformed or duplicate), for review.
  final List<CsvSkippedRow> skippedRows;

  const ContentImportState({
    this.phase = ImportPhase.idle,
    this.pluginId,
    this.url,
    this.collectionInfo,
    this.tracks = const [],
    this.resolvedCount = 0,
    this.failedCount = 0,
    this.error,
    this.errorKind,
    this.attempt = 1,
    this.phaseStartedAt,
    this.skippedRows = const [],
  });

  ContentImportState copyWith({
    ImportPhase? phase,
    String? pluginId,
    String? url,
    ImportCollectionSummary? collectionInfo,
    List<ImportTrackEntry>? tracks,
    int? resolvedCount,
    int? failedCount,
    String? error,
    ImportErrorKind? errorKind,
    int? attempt,
    DateTime? phaseStartedAt,
    bool clearError = false,
  }) {
    return ContentImportState(
      phase: phase ?? this.phase,
      pluginId: pluginId ?? this.pluginId,
      url: url ?? this.url,
      collectionInfo: collectionInfo ?? this.collectionInfo,
      tracks: tracks ?? this.tracks,
      resolvedCount: resolvedCount ?? this.resolvedCount,
      failedCount: failedCount ?? this.failedCount,
      error: clearError ? null : (error ?? this.error),
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      attempt: attempt ?? this.attempt,
      phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
      skippedRows: skippedRows,
    );
  }

  int get totalTracks => tracks.length;

  int countWhere(ImportMatchState s) =>
      tracks.where((t) => t.matchState == s).length;

  @override
  List<Object?> get props => [
        phase,
        pluginId,
        url,
        collectionInfo,
        tracks,
        resolvedCount,
        failedCount,
        error,
        errorKind,
        attempt,
        phaseStartedAt,
        skippedRows,
      ];
}
