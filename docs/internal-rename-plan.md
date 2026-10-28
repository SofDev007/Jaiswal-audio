# Internal rename Bloomee -> JARX (Batch C) - plan

Status: PLANNED, saved for later. Users never see any of these names; this is
only so the source code says JARX everywhere.

Stays forever (GPL-2.0): `LICENSE`, and the original-author credit in `NOTICE`.

Counts below were measured on commit 6e93f6a; uncommitted files add a few more.

## Steps (one commit each, build + test after each)

1. **Dart package name** - `pubspec.yaml` `name: Bloomee` -> `name: jarx`, then
   replace `package:Bloomee/` with `package:jarx/` in `lib/` and `test/`
   (~1,192 lines in ~191 files). Pure find/replace; `flutter analyze` proves it.
2. **Class / function names** - rename with the IDE (rename symbol), not sed:
   `BloomeePlayerCubit` (91 uses), `BloomeeMusicPlayer` (33), `BloomeeDialogAction`,
   `BloomeeSwitch`, `BloomeePlayerState`, `BloomeePlayerInitial`, `BloomeePlayer`,
   `showBloomeeDialog`, `BloomeeDialogSurface`, `BloomeeDialogBadge`,
   `BloomeeDialogTile`, `getBloomeeMusicPlayer` -> `Jarx...`.
3. **File and folder names** (`git mv`, then fix imports):
   `bloomee_player_cubit.dart`, `bloomee_player_state.dart`, `bloomee_player.dart`,
   `bloomee_updater_tools.dart`, `repository/bloomee/`, `widgets/bloomee_ui_kit/`.
4. **Localisation key** - `importBloomeeFiles` -> `importJarxFiles` in the 7
   `.arb` files, then regenerate with `flutter gen-l10n`.
5. **Rust library** `rust_lib_Bloomee` -> `rust_lib_jarx`, all at once:
   `rust/Cargo.toml` (+ `Cargo.lock`), `rust_builder/pubspec.yaml`, both
   `.podspec` files (rename the files too), `rust_builder/android/build.gradle`,
   `settings.gradle`, `AndroidManifest.xml`, linux/windows `CMakeLists.txt`,
   the dependency key in `pubspec.yaml`, and `stem:` in
   `lib/src/rust/frb_generated.dart`. Then delete `rust/target` and
   `build/` and do a clean build. Riskiest step: if the native library name
   and the stem disagree, the app crashes at start-up.
6. **Backup file names** (keep old backups working):
   write `jarxBackup/jarx_backup_dbv3.json` and `jarx_backup_dbv3.isar`, but
   when restoring also look for the old `bloomeeBackup/bloomee_backup_dbv3.*`
   names (`db_provider.dart` lines ~82, ~171). The live database is `dbv3.isar`
   and is NOT renamed, so user libraries are safe.
7. **Small internals** - temp folders (`bloomee_downloads`,
   `bloomee_runtime_embedded_art`, `bloomee_restore_`), notification channel
   ID `com.BloomeePlayer.notification.status`, log tags, comments.
8. **Assets** - delete `BloomeeLogo4.png` and `BloomeeLogoFG.png` (no Dart
   uses; also drop them from `pubspec.yaml`), replace `bloomee_new_logo_c.png`
   (2 uses) with the J1 JARX logo, point the macOS/Windows icon config at the
   J1 icon.
9. **Desktop / Discord** - goes with the Windows app phase: own Discord
   application ID + logo (or remove Rich Presence).

## Verify

- `flutter analyze` clean, `flutter test` green.
- `grep -ri bloomee lib test rust rust_builder` shows only the backup-name
  fallback from step 6.
- Clean release build, then on device: app starts, plugins load, playback,
  downloads, lyrics, create a backup and restore it, restore an OLD Bloomee
  backup, CSV/Spotify import.

## Notes

- Do steps 1-4 first (Dart only, low risk), step 5 alone, step 6 with a test.
- Needs approval for: running `flutter gen-l10n`, any codegen
  (`flutter_rust_bridge_codegen 2.12.0` if regenerating instead of hand-editing
  the stem).
