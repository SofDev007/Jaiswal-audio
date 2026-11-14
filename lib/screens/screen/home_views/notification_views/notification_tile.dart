import 'package:Bloomee/services/app_updater.dart';
import 'dart:developer';

import 'package:Bloomee/core/models/app_notification.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const NotificationTile({
    super.key,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: ListTile(
        // splashColor: Default_Theme.accentColor2.withValues(alpha: 0.1),
        onTap: () {
          if (notification.type == "app_update") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UpdateNotesView(notification: notification),
              ),
            );
          } else {
            log("Notification type not found: ${notification.type}");
          }
        },
        tileColor: Default_Theme.primaryColor1.withValues(alpha: 0.07),
        leading: const Icon(
          MingCute.medal_fill,
          color: Default_Theme.primaryColor1,
          size: 40,
        ),
        title: Text(
          notification.title,
          style: const TextStyle(
                  color: Default_Theme.accentColor2,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)
              .merge(Default_Theme.secondoryTextStyle),
        ),
        subtitle: Text(
          notification.body,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
                  color: Default_Theme.primaryColor2,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)
              .merge(Default_Theme.secondoryTextStyle),
        ),
      ),
    );
  }
}

/// The release notes of an update (every version the user skipped) and the
/// in-app updater: Download -> progress -> Android's install screen.
class UpdateNotesView extends StatefulWidget {
  const UpdateNotesView({super.key, required this.notification});
  final AppNotification notification;

  @override
  State<UpdateNotesView> createState() => _UpdateNotesViewState();
}

class _UpdateNotesViewState extends State<UpdateNotesView> {
  bool _downloading = false;
  double? _progress;
  String? _apk, _error;

  Future<void> _download(String url) async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      final path = await AppUpdater.download(url, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _apk = path);
      await AppUpdater.install(path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The download failed. Check your internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final url = n.url ?? '';
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Default_Theme.primaryColor1),
        title: const Text("What's new",
            style: TextStyle(color: Default_Theme.primaryColor1)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(n.title,
              style: const TextStyle(
                  color: Default_Theme.accentColor2,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SelectableText(
            // GitHub notes are Markdown; bold markers read badly as text.
            n.body.replaceAll('**', ''),
            style: const TextStyle(
                color: Default_Theme.primaryColor1, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (_downloading) ...[
            LinearProgressIndicator(
                value: _progress,
                color: Default_Theme.accentColor2,
                backgroundColor: Colors.white12),
            const SizedBox(height: 8),
            Text(
                _progress == null
                    ? 'Downloading...'
                    : 'Downloading... ${(_progress! * 100).round()}%',
                style: const TextStyle(color: Default_Theme.primaryColor2)),
          ] else if (url.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Default_Theme.accentColor2,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () => _apk != null
                  ? AppUpdater.install(_apk!)
                  : _download(url),
              icon: Icon(_apk != null
                  ? Icons.install_mobile_rounded
                  : Icons.download_rounded),
              label: Text(_apk != null ? 'Install update' : 'Download update'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_apk != null) ...[
            const SizedBox(height: 12),
            const Text(
                'If Android asks, allow JARX to install apps, then come back '
                'and tap Install update. Your music and sign-in stay.',
                style: TextStyle(color: Default_Theme.primaryColor2)),
          ],
        ],
      ),
    );
  }
}
