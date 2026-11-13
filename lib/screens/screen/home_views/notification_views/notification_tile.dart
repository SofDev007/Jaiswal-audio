import 'package:url_launcher/url_launcher.dart';
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
                builder: (context) => _UpdateNotes(notification: notification),
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

/// The full release notes of an update, with its download button.
class _UpdateNotes extends StatelessWidget {
  const _UpdateNotes({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final url = notification.url ?? '';
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
          Text(notification.title,
              style: const TextStyle(
                  color: Default_Theme.accentColor2,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SelectableText(
            // GitHub notes are Markdown; bold markers read badly as text.
            notification.body.replaceAll('**', ''),
            style: const TextStyle(
                color: Default_Theme.primaryColor1, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (url.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Default_Theme.accentColor2,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download update'),
            ),
        ],
      ),
    );
  }
}
