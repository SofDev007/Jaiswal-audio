# Device test: JARX launch animation

For device verification only, not a release. Nothing here runs until you
confirm the phone is connected and approve the install (step 4).

Target: realme 5 Pro (RMX1971), Android 11, arm64-v8a.

Commands are PowerShell. `adb` is not on PATH, so:

```powershell
$adb = "D:\Android\Sdk\platform-tools\adb.exe"
$pkg = "ls.bloomee.musicplayer"
$act = "$pkg/com.ryanheise.audioservice.AudioServiceActivity"
```

## 1. Build variant

**Profile, arm64 only, debug-signed** (this PC's `~/.android/debug.keystore`;
there is no `android/key.properties`). Profile mode has release performance
(AOT, no debug checks), which is what frame timings need, and is not a
release build.

```powershell
flutter build apk --profile --target-platform android-arm64 `
  --build-number <N> --dart-define=JARX_INTRO_TIMINGS=true
# -> build\app\outputs\flutter-apk\app-profile.apk
```

- `<N>`: the version code. `pubspec.yaml` says `3.0.4+0` (code 0), which can
  never update an installed copy. Use 1 if nothing is installed, otherwise
  the installed code + 1 (step 3).
- `JARX_INTRO_TIMINGS=true` prints one line of frame timings to logcat after
  the intro. It is compiled out of normal builds.
- **First build installs a Rust target on this PC.** Cargokit runs
  `rustup target add aarch64-linux-android` (about 30 MB) because only the
  Windows target is installed. NDK 28.2.13676358 is already present.

Second APK, only for the start-up error check (step 5f):

```powershell
flutter build apk --profile --target-platform android-arm64 `
  --build-number <N> --dart-define=JARX_SIMULATE_STARTUP_ERROR=true
Copy-Item build\app\outputs\flutter-apk\app-profile.apk app-profile-startup-error.apk
```

The error switch fails start-up before the database or anything else is
opened, so it cannot touch data.

## 2. Connect (you)

USB debugging on, cable in, accept the "Allow USB debugging" prompt.

```powershell
& $adb devices -l          # expect: RMX1971 ... device
```

## 3. Data safety check (read-only, before any install)

```powershell
& $adb shell pm list packages $pkg
& $adb shell dumpsys package $pkg | Select-String "versionCode|versionName|firstInstallTime"
& $adb shell pm path $pkg                      # e.g. package:/data/app/.../base.apk
& $adb pull <that path> installed-base.apk
& "D:\Android\Sdk\build-tools\<latest>\apksigner.bat" verify --print-certs installed-base.apk
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -alias androiddebugkey -storepass android | Select-String "SHA256"
```

| What the check shows | What happens to your data | Go ahead? |
|---|---|---|
| Not installed | Nothing to lose | Yes, `<N>` = 1 |
| Installed, same certificate as this PC's debug key | Updated in place, library kept | Yes, `<N>` = installed code + 1 |
| Installed, **different certificate** (e.g. official Bloomee from GitHub, code 202) | An in-place update is impossible; the only route is uninstall, which **deletes the library** | **Stop.** Decide first (below) |

If the certificate differs, the options are:

- **Back up first (keeps your data).** Settings → Storage → back up the
  database and export JSON, then copy the files to the PC
  (`& $adb pull /sdcard/Download/<file>`). Then uninstall, install, restore.
- **Install the test build side by side** under a test-only app ID (for
  example `ls.bloomee.musicplayer.devtest`). This needs a small, opt-in
  Gradle change that I have not made. Your installed app and its data are
  untouched.

Either way, take the in-app backup before installing.

## 4. Install (only after your approval)

```powershell
& $adb install -r build\app\outputs\flutter-apk\app-profile.apk
```

- `-r` replaces the app and keeps its data. `-d` (downgrade) is never used,
  and nothing is uninstalled.
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` or `INSTALL_FAILED_VERSION_DOWNGRADE`
  means stop, not retry. `flutter run` is not used, because when an install
  fails it uninstalls the old app and retries, which would wipe its data.
- **Data impact of the update:** the database gains the `TrackSignalDB`
  collection (additive; existing rows unchanged). Whether an older build can
  still open it afterwards is unverified, so keep the step 3 backup.

## 5. Tests

Before each cold launch: `& $adb shell am force-stop $pkg`.

### a. Cold launch, recording, frame timings

```powershell
& $adb logcat -c
$rec = Start-Process -PassThru -NoNewWindow $adb `
  "shell screenrecord --bit-rate 20000000 --time-limit 8 /sdcard/jarx_cold.mp4"
Start-Sleep -Milliseconds 800
& $adb shell am start -W -n $act            # note TotalTime
Wait-Process -Id $rec.Id
& $adb pull /sdcard/jarx_cold.mp4 .\device-test\jarx_cold.mp4
& $adb logcat -d -s flutter | Select-String "JARX intro timings"
```

Pass:

- The recording shows ink, then the intro, then Home. No white or black
  flash at the system-splash hand-off or at the 200 ms cross-fade. I check
  this frame by frame, flagging any frame much brighter than ink before the
  intro starts.
- The timings line reports p90 build and raster at or under 16.7 ms and few
  frames over budget. Watch the first ~0.4 s: start-up work (opening the
  database) runs then, while the pulse is still off-screen.

### b. Tap to skip

Cold launch, then about 0.5 s later:

```powershell
& $adb shell input tap 540 1200
```

Pass: Home within about 250 ms if start-up has finished; otherwise the last
frame holds until it does. Record as in (a) to see it.

### c. Start-up hand-off

Read the timestamps in `& $adb logcat -d -s flutter` ("Plugin system
initialized", "Bootstrap") against the end of the intro in the recording.
Pass: the intro never waits for start-up, and Home appears only after both
are done, with no blank frame in between.

### d. Warm resume

```powershell
& $adb shell input keyevent KEYCODE_HOME
& $adb shell am start -W -n $act
```

Pass: straight back to the app, no intro.

### e. Remove animations

```powershell
$saved = "window_animation_scale","transition_animation_scale","animator_duration_scale" |
  ForEach-Object { @{ k = $_; v = (& $adb shell settings get global $_) } }
$saved | ForEach-Object { & $adb shell settings put global $_.k 0 }
# cold launch + record as in (a)
$saved | ForEach-Object { & $adb shell settings put global $_.k $_.v }   # restore
```

Pass: the last frame shows for about 300 ms with no motion, then Home.
Settings are restored afterwards.

### f. Start-up error screen

```powershell
& $adb install -r app-profile-startup-error.apk
# cold launch, screenshot:
& $adb exec-out screencap -p > .\device-test\startup_error.png
& $adb install -r build\app\outputs\flutter-apk\app-profile.apk   # back to normal
```

Pass: the intro plays, then "JARX could not start." with the message, and no
hang. No data is read or written in this build.

### g. Android 12+ system splash

The realme 5 Pro runs Android 11, so it never shows the Android 12 system
splash. Checking the plain-ink, no-icon hand-off needs an Android 12+ phone.

## 6. Clean up

```powershell
& $adb shell rm /sdcard/jarx_cold.mp4
```

Also check the animation settings were restored (5e). The profile app stays
installed; tell me if you want something else.
