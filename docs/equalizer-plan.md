# Equalizer: findings and plan

Checked 2026-10-23 on the realme 5 Pro (Android 11) with JARX build 3–4.

## Findings

1. **The in-app (built-in) EQ runs.** It is an mpv audio filter
   (`af=lavfi=[equalizer=...]`, `lib/services/player/player_engine.dart`).
   A read-back after setting it returned the full 8-band graph, and with mpv
   warnings routed to logcat there was no filter error or "disabling filter"
   message when a track loaded with the EQ on. Not yet confirmed by ear.
2. **JARX has no audio session to hand to other EQ apps.** The bundled mpv
   (`media_kit_libs_android_audio` 1.3.8, libmpv-android-audio-build v1.1.8)
   appears to output through OpenSL ES and exposes no Android audio session
   ID. JARX never sends `OPEN/CLOSE_AUDIO_EFFECT_CONTROL_SESSION`.
3. **Installed external EQs.**
   - `com.jazibkhan.equalizer` (Equalizer FX): has a receiver for
     `OPEN/CLOSE_AUDIO_EFFECT_CONTROL_SESSION` (per-app mode) and a
     system-wide mode. Without a session from JARX it can only reach JARX in
     system-wide mode.
   - realme's Dirac (`se.dirac.acs`, `com.oppo.multimedia.dirac`): a
     system-wide sound effect.
4. **"Device EQ" in JARX opens nothing.** It turns the in-app EQ off and shows
   "Configure your device EQ in Settings → Sound & Vibration → Equalizer".
5. Unrelated mpv errors seen: `No cache data directory supplied` /
   `Failed to create file cache` (the on-disk stream cache is not set up;
   the in-memory cache still works).

## What is possible

| Wanted | Possible? |
|---|---|
| In-app EQ on → external EQ does not touch JARX | Only for per-app EQs. A system-wide EQ (Equalizer FX global mode, Dirac) applies to every app's output and no app can block it. |
| In-app EQ off → external EQ works | System-wide EQs already do. Per-app mode needs a session ID from mpv, which this mpv build does not expose. |

## Plan (needs approval)

1. **Confirm by ear (5 minutes, you).** Play a song, turn Equalizer FX and
   Dirac off, then switch the in-app preset between Flat and Bass Boost.
   If there is an audible change, the in-app EQ works and the problem was
   the external EQs stacking on top.
2. **Make the two modes explicit in the EQ screen.**
   - Built-in EQ: a note "Turn off other equalizer apps (Equalizer FX,
     Dirac) while using the built-in EQ; JARX cannot switch them off."
   - Device EQ: a button that opens the installed EQ app's panel
     (`DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`) instead of a text hint.
3. **Optional, larger: true per-app hand-off.** Needs an mpv build whose
   Android output is AudioTrack with a known session ID (a custom
   libmpv-android build or a different audio backend for Android). Then JARX
   sends OPEN when the in-app EQ is off and CLOSE when it is on. This is a
   dependency and native-build change: its own phase.
4. Remove the temporary EQ diagnostics in `player_engine.dart` (mpv log
   forwarding and the read-back print) once 1 is done.

## Update 2026-10-26: per-app hand-off implemented (build 16, not yet heard on device)

Item 3 turned out not to need a custom mpv build. The bundled libmpv has
mpv's AudioTrack output with `audiotrack-session-id`; media_kit just forces
`ao=opensles`, and it already registers the Java VM with mpv.

- `PlayerEngine` generates a session (`AndroidAudioManager.generateAudioSessionId`),
  sets `audiotrack-session-id` and `ao=audiotrack,opensles` on both players
  (OpenSL ES is the fallback), and waits for that before opening tracks.
- In-app EQ **off** (switch off, or "Device EQ" source): JARX broadcasts
  `OPEN_AUDIO_EFFECT_CONTROL_SESSION`, so per-app equalizers attach to JARX.
- In-app EQ **on**: JARX broadcasts `CLOSE_…`, so they let go of JARX.
- `MainActivity` sends the broadcasts implicitly and also directly to each
  receiver (Android 8+ drops implicit ones for manifest receivers; listed in
  `<queries>`), and opens the EQ app's panel ("Open equalizer app" in Device EQ).
- Still true: system-wide effects (an EQ app's global mode, Dolby/Dirac in the
  phone's sound settings) apply to every app and cannot be blocked.

Test on device: (a) audio still plays; (b) Device EQ → "Open equalizer app"
opens Equalizer FX / Wavelet and its changes are heard; (c) switch to Built-in
EQ on → the external app's changes stop; (d) crossfade between tracks still
works; (e) `adb logcat | grep -i "audiotrack\|opensles"` shows mpv using
AudioTrack.
