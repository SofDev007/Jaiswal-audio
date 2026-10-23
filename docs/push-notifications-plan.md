# Push notifications (Firebase Cloud Messaging): plan for JARX v2

Status: PROPOSAL, not approved. Nothing below is implemented yet.
Written 2026-10-23.

## Goal

As the admin, send a short message (title + body) from the Firebase Console that
reaches every JARX install, including installs where the app is closed.

Scope for v2: **Android only.** iOS needs a paid Apple Developer account and
APNs keys (later phase). Windows, Linux and macOS are not changed.

## What exists today (audit)

| Item | State |
|---|---|
| Firebase, FCM, OneSignal, any backend | None |
| `POST_NOTIFICATIONS` permission | Already in `AndroidManifest.xml` |
| Monochrome status icon | `drawable/ic_stat_jarx`, already used by audio_service |
| `permission_handler` | Already a dependency |
| Settings storage | `SettingsDAO` / `SettingKeys` (`getSettingBool`, `putSettingBool`) |
| Startup hook | `_initApp()` in `lib/main.dart` (runs behind the JARX launch screen) |
| Android package | `com.jaiswal.jarx`, AGP 8.9.1, Kotlin 2.1.0, minSdk from Flutter (21+) |
| Version | `1.0.0+1` |

## Decisions needed before implementing

1. **Who owns the Firebase project.** You create it under your Google account
   (I can't do it for you).
2. **`google-services.json` in a public repo.** Recommended: add it to
   `.gitignore` and keep it only on your machine. Its API key is not secret by
   Firebase's design, but the repo is public, so restrict the key to the
   Android app in Google Cloud Console anyway.
3. **Topic name.** Proposed: `announcements` (one topic, every install).
4. **Opt-out.** Proposed: a Settings switch "Announcements", ON by default.
5. **Message shown while the app is open.** Android does not show FCM
   notifications for a foreground app. Proposed: show it as an in-app SnackBar
   (no extra package). The alternative is `flutter_local_notifications` (a new
   dependency).
6. **Version number.** Proposed: `2.0.0+2`. `versionCode` must be higher than
   what's on devices, and the APK must use the same signing key, or it won't
   install over the existing app.

## Steps

### A. Firebase Console (you do this)

1. https://console.firebase.google.com → Add project → name `JARX`.
   **Turn Google Analytics OFF** (not needed, keeps data collection minimal).
2. Add app → Android → package `com.jaiswal.jarx`, nickname `JARX Android`.
   SHA-1 is not needed for FCM.
3. Download `google-services.json` and place it at `android/app/google-services.json`.
4. Project settings → Cloud Messaging: check that "Firebase Cloud Messaging API (V1)" is
   enabled (it is by default on new projects).

### B. Gradle (2 files)

- `android/settings.gradle.kts`, in `plugins {}`:
  `id("com.google.gms.google-services") version "<current 4.4.x>" apply false`
- `android/app/build.gradle.kts`, in `plugins {}`:
  `id("com.google.gms.google-services")`

### C. Android manifest and notification channel

- `AndroidManifest.xml`, inside `<application>`:
  - `com.google.firebase.messaging.default_notification_icon` → `@drawable/ic_stat_jarx`
  - `com.google.firebase.messaging.default_notification_channel_id` → `jarx_announcements`
- Create the `jarx_announcements` channel ("Announcements") at startup (a few lines
  in `MainActivity.kt`), so users can mute announcements without muting
  playback controls. Without it, Android uses a generic "Miscellaneous" channel.

### D. Dart

1. `flutter pub add firebase_core firebase_messaging` (with `D:\flutter-3.35.4`),
   and let the resolver pick versions compatible with Flutter 3.35.4. Restore
   unrelated `pubspec.lock` churn afterwards, as with other builds.
2. New file `lib/services/push_service.dart`, roughly 50 lines:
   - `PushService.init()`: returns immediately unless `Platform.isAndroid`.
     Calls `Firebase.initializeApp()` and `requestPermission()` (the prompt
     appears only on Android 13+). Subscribes to `announcements` if the
     setting is ON.
   - `FirebaseMessaging.onMessage` → in-app SnackBar with title and body.
   - `setEnabled(bool)` → `subscribeToTopic` / `unsubscribeFromTopic`, and saves
     the setting.
   - Everything is in try/catch. With no network, no Google Play Services or
     a Firebase error, the app must still start normally.
3. `lib/main.dart` → `_initApp()`: `unawaited(PushService.init())` after
   `bootstrapApp()`, so the launch screen never waits on Firebase.
4. Add a `SettingKeys.announcements` key, and an "Announcements" switch in
   Settings (alongside the other app-UI toggles), wired to `PushService.setEnabled`.

Not in v2: tapping a notification to open a song or playlist (deep links), data-only messages,
a background message handler (not needed for notification messages, which the system
displays itself), per-user targeting.

### E. Desktop safety check

`firebase_core` includes a Windows plugin that downloads the Firebase C++ SDK
during the Windows build. All calls are guarded by `Platform.isAndroid`, but
the dependency still affects the Windows build. Run `flutter build windows`
once, or record it as a known issue for the Windows app phase.

## Admin runbook: sending a notification

Firebase Console → **Messaging** → **New campaign** → **Notifications** →
title + text → Target: **Topic** `announcements` → **Send now**
(or schedule it).

Things to know:
- Only installs running v2 or later receive messages. Older installs never do.
- Delivery usually takes seconds. On aggressive battery savers (realme/ColorOS), it can be delayed.
- A **force-stopped** app (Settings → Force stop) receives nothing until it is opened
  again. This is how Android works, not a bug.
- Users who turned Announcements off, denied the permission or muted the channel
  don't see it.

## Test plan (debug build first, then the v2 APK)

On the realme 5 Pro, plus one Android 13+ device or emulator for the permission prompt:

1. Fresh install: on Android 13+, the permission prompt appears. Allowing or denying it doesn't affect startup.
2. App in foreground → send → SnackBar appears.
3. App in background → send → system notification with the JARX icon.
4. App swiped away from recents → send → notification arrives.
5. Phone rebooted, app not opened → send → notification arrives.
6. Announcements switch OFF → send → nothing arrives. Switch ON again → it arrives again.
7. Airplane mode at launch → app starts normally. Notification arrives after reconnecting.
8. Emulator without Google Play Services → app starts normally, nothing crashes.
9. Playback notification and media controls still behave exactly as before.
10. Upgrade test: install v2 over the existing v1 install. Library and settings are kept.
11. Force stop → send → nothing (expected). Open app → later sends arrive.

Results go into `docs/pending-verification.md`.

## Files touched

- `android/settings.gradle.kts`, `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`, `MainActivity.kt`
- `android/app/google-services.json` (local only, if gitignored) and `.gitignore`
- `pubspec.yaml`, `pubspec.lock`
- `lib/services/push_service.dart` (new), `lib/main.dart`
- `SettingKeys` file and one settings view
- `docs/pending-verification.md`

## Privacy

- Each install gets an FCM token, which Google stores. JARX sends no user data,
  listening history or account information.
- Analytics stays off.
- Add a line about this to the README or About screen before release.

## Rollout (to plan together after the APK test)

Open questions for the rollout plan:
- How users get v2: GitHub Release on `SofDev007/Jaiswal-audio`, direct APK
  share, or something else. The update checker is currently OFF, so v1 users
  won't be told an update exists.
- Whether to send a first "welcome to v2" announcement as a smoke test.
- Signing key: confirm the release keystore used for v1 is available, so v2
  installs over v1.
- Rollback: what to do if v2 has a problem (keep the v1 APK available).
