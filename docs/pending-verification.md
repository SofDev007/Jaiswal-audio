# Pending verification

Work that is implemented and passes automated tests but has not been verified
in the real app. Tick items off with the date and device when checked.

## Recommendations v1 (frozen, approved 2026-10-13)

- [ ] **Real-device autoplay.** Play a user-chosen track to the end of the
  queue; confirm batches of 5 are queued, each shows its reason in the Up Next
  panel, recommendations stay seeded by the user's track (not by auto-queued
  ones), and early skips / completions are recorded.
- [ ] **Real provider behaviour (ytmusic, JioSaavn).** Confirm what each
  plugin actually returns for `getRadioTracks`, `getArtistDetails`
  (`topTracks`, `relatedArtists`) and search. If `relatedArtists` or
  `topTracks` are empty, those sources simply contribute nothing; check the
  remaining quality is acceptable.
- [ ] **Isar migration and backward compatibility.** The `TrackSignalDB`
  collection was added to `lib/services/db/global_db.dart`. Verify an
  existing install upgrades without data loss, and whether an older build can
  still open a database that contains the new collection (downgrade path).
- [ ] **`libisar.dll` test environment.** Tests that open Isar fail on this
  Windows machine with "Failed to load dynamic library ...\libisar.dll"
  (`test/legacy_migration_service_test.dart` fails the same way at HEAD).
  Because of this, `TrackSignalDAO` has no automated test yet. Fix the test
  environment, then add a DAO test.

## JARX launch animation (Option C "Flatline")

- [ ] **Hand-off:** cold-start on the realme 5 Pro (Android 11) and on an
  Android 12+ phone: no white/black flash, no jump between the system splash
  (plain ink, no icon) and the first intro frame.
- [ ] **Frame times:** `flutter run --profile` (or `--release` with the
  performance overlay) on the realme 5 Pro; target 60 fps for the whole 2.8 s.
  Watch the first ~0.4 s: start-up work (opening the database) runs then,
  while the head is still off-screen.
- [ ] **Screen recording** of a cold start (`adb shell screenrecord`).
- [ ] Tap-to-skip, warm resume (no replay), and "Remove animations" on.
- [ ] iOS LaunchScreen (plain ink) needs a Mac to build and check.

## JARX loading indicator

- [ ] Look at the bouncing-bars indicator on a device in the busiest places:
  search (results and the small suggestions indicator), album/artist/playlist
  pages, the mini player's play button while a track resolves, plugin manager
  buttons, and the import screens. Check small (16–20 px) ones are readable.

## Playlist import (Phases 1–2)

- [ ] Spotify link import of a large playlist against the real
  `spotify-importer` plugin: timeouts, retry, cancel, and which error kind real
  plugin messages map to.
- [ ] CSV import with real Exportify / TuneMyMusic files on a device.
