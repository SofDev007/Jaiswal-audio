import 'dart:io';

import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/services/player/stream_quality_selector.dart';
import 'package:Bloomee/screens/screen/home_views/setting_views/setting_shared_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DownloadSettings extends StatefulWidget {
  const DownloadSettings({super.key});

  @override
  State<DownloadSettings> createState() => _DownloadSettingsState();
}

Future<bool> storagePermission() async {
  final DeviceInfoPlugin info = DeviceInfoPlugin();
  final AndroidDeviceInfo androidInfo = await info.androidInfo;
  debugPrint('releaseVersion : ${androidInfo.version.release}');
  final int androidVersion = int.parse(androidInfo.version.release);
  bool havePermission = false;

  if (androidVersion >= 13) {
    final request = await [
      Permission.videos,
      Permission.photos,
    ].request();
    havePermission =
        request.values.every((status) => status == PermissionStatus.granted);
  } else {
    final status = await Permission.storage.request();
    havePermission = status.isGranted;
  }

  if (!havePermission) {
    await openAppSettings();
  }

  return havePermission;
}

class _DownloadSettingsState extends State<DownloadSettings> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Default_Theme.themeColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Default_Theme.primaryColor1,
                size: 24,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          l10n.downloadSettingTitle,
          style: const TextStyle(
            color: Default_Theme.primaryColor1,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ).merge(Default_Theme.secondoryTextStyleMedium),
        ),
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              SettingSectionHeader(label: l10n.settingsQuality),
              SettingCard(
                children: [
                  SettingQualityChipRow(
                    icon: MingCute.folder_download_fill,
                    title: l10n.downloadSettingQuality,
                    subtitle: l10n.downloadSettingQualitySubtitle,
                    options: AudioStreamQualityPreference.values
                        .map((q) => q.label)
                        .toList(),
                    selected: state.downQuality,
                    onSelected: (v) =>
                        context.read<SettingsCubit>().setDownQuality(v),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SettingSectionHeader(label: l10n.downloadOverTitle),
              const _DownloadOverCard(),
              const SizedBox(height: 28),
              SettingSectionHeader(label: l10n.settingsStorage),
              SettingCard(
                children: [
                  if (Platform.isAndroid)
                    _DownloadLocationRow(downPath: state.downPath)
                  else
                    SettingNavTile(
                      icon: MingCute.folder_fill,
                      title: l10n.downloadSettingFolder,
                      subtitle: state.downPath,
                      onTap: () async {
                        FilePicker.platform.getDirectoryPath().then((value) {
                          if (value != null) {
                            context.read<SettingsCubit>().setDownPath(value);
                          }
                        });
                      },
                    ),
                  if (!Platform.isAndroid) ...[
                    const SettingDivider(),
                    SettingNavTile(
                      icon: MingCute.refresh_1_line,
                      title: l10n.downloadSettingResetFolder,
                      subtitle: l10n.downloadSettingResetFolderSubtitle,
                      roundBottom: true,
                      onTap: () =>
                          context.read<SettingsCubit>().resetDownPath(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

/// Android: save downloads to phone storage or the SD card. Both are JARX's
/// own folders (no storage permission needed). Chosen once and remembered;
/// only new downloads go to the new place.
class _DownloadLocationRow extends StatelessWidget {
  const _DownloadLocationRow({required this.downPath});
  final String downPath;

  static const _phone = 'Phone storage', _sd = 'SD card';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Directory>?>(
      // [0] is phone storage; a second entry is a removable SD card.
      future: getExternalStorageDirectories(type: StorageDirectory.downloads),
      builder: (context, snap) {
        final dirs = snap.data ?? const <Directory>[];
        final sd = dirs.length > 1 ? dirs[1].path : null;
        final onSd = sd != null && downPath.startsWith(sd);
        return SettingQualityChipRow(
          icon: MingCute.folder_fill,
          title: 'Save downloads to',
          subtitle: sd == null
              ? 'No SD card found, so downloads go to phone storage.'
              : 'New downloads are saved here. Songs already downloaded '
                  'stay where they are.',
          options: [_phone, if (sd != null) _sd],
          selected: onSd ? _sd : _phone,
          onSelected: (v) {
            final path = v == _sd ? sd : dirs.firstOrNull?.path;
            if (path != null) context.read<SettingsCubit>().setDownPath(path);
          },
        );
      },
    );
  }
}

/// "Download over": Wi-Fi (only on Wi-Fi) or Mobile data (any network,
/// the default).
class _DownloadOverCard extends StatefulWidget {
  const _DownloadOverCard();

  @override
  State<_DownloadOverCard> createState() => _DownloadOverCardState();
}

class _DownloadOverCardState extends State<_DownloadOverCard> {
  late bool _wifiOnly =
      context.read<DownloaderCubit>().downloadOverWifiOnly;

  Future<void> _set(bool wifiOnly) async {
    setState(() => _wifiOnly = wifiOnly);
    await context.read<DownloaderCubit>().setDownloadOverWifiOnly(wifiOnly);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingCard(
      children: [
        SettingRadioTile<bool>(
          title: l10n.downloadOverWifi,
          subtitle: l10n.downloadOverWifiSubtitle,
          value: true,
          groupValue: _wifiOnly,
          onChanged: (_) => _set(true),
        ),
        const SettingDivider(),
        SettingRadioTile<bool>(
          title: l10n.downloadOverMobile,
          subtitle: l10n.downloadOverMobileSubtitle,
          value: false,
          groupValue: _wifiOnly,
          onChanged: (_) => _set(false),
        ),
      ],
    );
  }
}
