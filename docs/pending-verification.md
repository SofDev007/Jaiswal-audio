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

## Import cancellation (Rust stop flag)

- [x] Device test, 2026-10-20, realme 5 Pro (RMX1971, Android 11), profile
  APK (versionCode 1, Flutter 3.35.4, JDK 17), 57-track Spotify playlist:
  - Cold start 1.6 s; first-run plugin setup completed; no bridge errors,
    Rust panics, crashes or ANRs in the whole session's log.
  - Cancel during the track fetch: the plugin made no further requests
    after the request already in flight finished (the uncancelled run kept
    fetching for ~5 s more); the screen returned to the link field at once.
  - An import started straight after the cancel fetched all 57 tracks in
    ~20 s with no plugin-busy error, then matched 55 confident, 2 to check,
    0 failed, and saved.
  - "Stop and review" while matching stopped at once.
  - Evidence is indirect: the cubit's `dart:developer` `log()` messages do
    not reach logcat in profile builds.
- [ ] Not yet seen on a device: timeout then retry (no timeout occurred; not
  forced), and cancelling a request stuck on the network (the in-flight
  request finished in 280 ms, so the 50 ms abort poll was not exercised).
- **Known limitation (fix not approved):** unloading a plugin that is stuck
  in a loop without making requests hangs, because `unload_plugin` waits for
  the same plugin lock (`rust/src/api/plugin/plugin.rs`, `arc.lock().await`
  in `unload_plugin`). Only an app restart recovers such a plugin.
- Known limitations: an unchecked WebAssembly loop cannot be interrupted; an
  HTTP request already sent is not aborted (its thread runs out in the
  background, up to the client's 30 s timeout); a cancel issued before Rust
  picks up a just-sent request misses it (the next call's cancel and the 40 s
  busy guard cover it).

## JARX rename (Android) — checked 2026-10-23, realme 5 Pro

- [x] Installs as `com.jaiswal.jarx` next to the old test app; launcher icon
  J1 with the label "JARX"; launch animation; "Welcome to JARX";
  "Setting up JARX"; no update pop-up or "What's new"; no Updates entry in
  Settings; About shows the J1 logo, JARX, the tagline, the credit line and
  v1.0.0; media notification shows the white J1 mark and "JARX"; "Import
  JARX files"; a 57-track Spotify import fetched, matched (55/2/0) and saved.
- [ ] Restoring a backup exported from the old Bloomee test app (needs file
  pickers on both apps; not tested).
- [ ] iOS bundle ID, name and icon: changed in code, needs a Mac to build.
- Build note: a build after Dart changes once shipped the old `libapp.so`;
  clear `.dart_tool/flutter_build` and `build/app/intermediates/flutter`
  before building, and check a new string is inside the APK.

## Player and Home changes — 2026-10-23, realme 5 Pro

- [x] Back with the player open over a playlist slides the player down and
  keeps the playlist page (also covered by `test/player_back_test.dart`).
- [x] Home: big chart cards removed; greeting header with the J1 logo;
  Continue listening row.
- [x] Home "For you" row shows on device (Judas, TiK ToK, Paparazzi with
  reason labels). It first gathered 0: it ran before the plugins loaded,
  and plugin calls queue behind the Home sections (a radio call took 26 s
  against the gatherer's 8 s timeout). Home now waits for the plugins and
  uses a 60 s timeout.
- [ ] Volume drag on the cover is removed in code; swipes injected over adb
  do not register on this phone, so check by hand that dragging the cover
  no longer changes the volume.
- [ ] Player autoplay recommendations use the same 8 s timeout and likely
  return nothing on slow connections; see Recommendations v1 above.
- [ ] Equalizer: see `docs/equalizer-plan.md` (needs a listening test).
- [x] Rust logging capped at warnings in release builds (`init_app` in
  `rust/src/api/bridge.rs`, `log` declared in `rust/Cargo.toml`). First
  minute after launch: 0 verbose Rust lines, ~680 lines in total (was
  ~7,000/min). Most of the rest is Android's `E/Parcel` NULL-string message.

## JioSaavn and search (2026-10-23, build 12)

- [ ] Country change installs JioSaavn: build 11 did not (no `jisaavn` in
  Plugins after switching to India). Build 12 prints each step to logcat
  (`Newly allowed: ...`); re-select India and read those lines.
- [ ] "JioSaavn" (not "jisaavn") shows in Search sources, Plugins and
  Plugin Defaults once installed.
- [ ] Search remembers the last source tapped (existing `searchPluginId`
  setting; already worked before these changes).
- [ ] Search time: `Search on <plugin> took N ms` in logcat; compare
  JioSaavn and YouTube Music, Wi-Fi and mobile data.
- [ ] For you waits for the Home sections and reuses its saved picks for 6 h.

## Device findings (2026-10-20, realme 5 Pro)

- First launch shows the upstream update checker's "Update Available
  (3.0.4+202)" dialog over "What's new". To be turned off in the rename phase.
- Upstream branding still visible: app label "Bloomee", "Welcome to
  Bloomee", "Setting up Bloomee", About page "BloomeeTunes · Crafting
  symphonies in code".
- One `Skipped 32 frames` at cold start.

## Playlist import (Phases 1–2)

- [ ] Spotify link import of a large playlist against the real
  `spotify-importer` plugin: timeouts, retry, cancel, and which error kind real
  plugin messages map to. (A 57-track playlist imported, cancelled and
  re-imported cleanly on 2026-10-20; still to do: a playlist of several
  hundred tracks, a real timeout, error-kind mapping.)
- [ ] CSV import with real Exportify / TuneMyMusic files on a device.
