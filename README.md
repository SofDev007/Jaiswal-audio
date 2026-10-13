# JARX

**Jaiswal Audio Response eXperience**: a personal music player built with
Flutter and Rust. It plays your local music alongside streams from a secure,
WebAssembly plugin system, and learns from what you listen to, on your device.

## Features

- **Plugins:** `.bex` plugins for search, streaming, charts, lyrics and
  playlist import, run in a sandboxed Rust/WebAssembly runtime.
- **Local music:** your device's music in the same library as streams.
- **Playlist import:** Spotify links (with retries, cancel and clear errors)
  and CSV exports (Exportify, TuneMyMusic and similar), with match confidence
  shown for every track.
- **On-device recommendations:** autoplay ranked by what you play, like and
  skip, with a short reason for each pick. Nothing leaves your device.
- **Lyrics:** time-synced, with offset adjustment.
- **Equalizer and crossfade.**
- **Last.fm scrobbling** and **Discord Rich Presence** (optional).
- **Backup and restore** of your library and settings (JSON, M3U).
- **Android, Windows and Linux**, with native media controls.
- **Interface in 7 languages:** English, Hindi, German, Spanish, Japanese,
  Korean and Chinese.

## Building

Requirements: Flutter (stable), Rust (`rustup`), and for Android the Android
SDK and NDK. The Rust part is built automatically by the Flutter build.

```sh
flutter pub get
flutter run                 # debug on a connected device or desktop
flutter test                # unit and widget tests
```

## Credits and license

JARX is based on BloomeeTunes and, like it, is licensed under the GNU General
Public License, version 2. See [NOTICE](NOTICE) and [LICENSE](LICENSE).
