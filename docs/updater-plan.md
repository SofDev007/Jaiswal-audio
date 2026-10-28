# In-app update checker (Batch B) - plan

Status: PLANNED, do not implement yet. Switch on together with the login phase.

Goal: when a new JARX version is published on GitHub, users of the app are
told and can download it.

## What already exists (reuse, don't rewrite)

- `lib/services/bloomee_updater_tools.dart`
  - `githubUpdate()` reads `https://api.github.com/repos/<owner>/<repo>/releases/latest`,
    parses the tag (`v1.0.1+2`), compares with the installed version via
    `isUpdateAvailable()`, and picks the download with `extractUpUrl()`
    (matches `android` / `windows` in the asset file name).
  - `getAppUpdates()` is currently a stub that returns "no update".
  - `fetchChangelog()` fetches a CHANGELOG.md.
- `GlobalEventsCubit.checkForUpdates()` emits `UpdateAvailable` / `WhatIsNewState`.
- `GlobalEventListener` shows the update dialog and opens `downloadUrl`.
- `CheckUpdateView` (manual "check for updates" screen), the `autoUpdateNotify`
  setting, and the Updates settings tile (removed in the rename phase).

## Changes

1. `githubUpdate()`: repoint the URL to
   `https://api.github.com/repos/SofDev007/Jaiswal-audio/releases/latest`.
2. `getAppUpdates()`: call `githubUpdate()`, and on any error return
   `{'results': false, 'changelogs': null}` (no crash when offline).
   Delete `sourceforgeUpdate()`.
3. `GlobalEventsCubit.checkForUpdates()`: use `updates['download_url']` instead
   of the hard-coded `https://bloomee.sourceforge.io/`.
4. `fetchChangelog()`: point at
   `https://raw.githubusercontent.com/SofDev007/Jaiswal-audio/main/CHANGELOG.md`
   (CHANGELOG.md must first be rewritten as JARX's own changelog).
5. `CheckUpdateView`: replace the two Bloomee links with
   `https://github.com/SofDev007/Jaiswal-audio/releases`.
6. Restore the Updates tile in Settings (auto-notify toggle + "Check now").
7. CI (`.github/workflows/main.yml`): name assets
   `jarx_android_v<ver>+<build>_<abi>.apk` / `jarx_windows_x64_v<ver>+<build>.zip`
   so `extractUpUrl()` still matches.
8. Gate: one switch so it only turns on with login (decide at the login phase:
   on for everyone once login ships, or only for signed-in users).

## How to publish an update (once live)

1. Bump `version:` in `pubspec.yaml`, e.g. `1.0.1+2` (build number must go up).
2. Build the release APK signed with the SAME release keystore as before.
3. Create a GitHub release with tag `v1.0.1+2` and attach the APK.
4. Installed apps see it on their next launch.

## Must-knows

- Android only installs an update over the old app if both are signed with the
  same key. Create the release keystore once, back it up, never lose it.
- The app opens the APK link; Android downloads it and asks the user to allow
  "install unknown apps" once. Silent/automatic install is not possible outside
  the Play Store; an in-app downloader would need `REQUEST_INSTALL_PACKAGES`
  (skipped, add only if asked).
- GitHub allows 60 unauthenticated API calls per hour per IP; one check per
  launch is fine.
- Flutter split-per-ABI builds add 1000/2000/... to the build number; the
  existing `% 1000` in `githubUpdate()` handles that, keep it.

## Test

- Unit test for `isUpdateAvailable()` (newer/older/equal version and build).
- Device: install build N, publish N+1 as a release, relaunch, dialog appears,
  link downloads the right APK, installs over the old app with data kept.
