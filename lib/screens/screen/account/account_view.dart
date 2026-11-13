// Settings › Account: who is signed in, Sign out, Delete my account.

import 'package:Bloomee/services/account/sync.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/services/account/account.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Account.instance.user;
    const fg = Default_Theme.primaryColor1;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: fg),
        title: const Text('Account',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Default_Theme.accentColor2.withValues(alpha: 0.3),
              backgroundImage: (user?.photo.isNotEmpty ?? false)
                  ? CachedNetworkImageProvider(user!.photo)
                  : null,
              child: (user?.photo.isNotEmpty ?? false)
                  ? null
                  : const Icon(Icons.person, size: 44, color: fg),
            ),
          ),
          const SizedBox(height: 16),
          Text(user?.name ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: fg, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(user?.email ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: fg.withValues(alpha: 0.7))),
          const SizedBox(height: 32),
          ValueListenableBuilder<bool>(
            valueListenable: Sync.instance.busy,
            builder: (context, busy, _) => ValueListenableBuilder<DateTime?>(
              valueListenable: Sync.instance.lastSynced,
              builder: (context, last, _) => _Tile(
                icon: Icons.sync_rounded,
                title: busy ? 'Syncing…' : 'Sync now',
                subtitle: 'Playlists, Liked, recent plays and taste follow you '
                    'to every phone. ${last == null ? 'Not synced yet.' : 'Last synced ${_when(last)}.'}',
                onTap: () async {
                  final error = await Sync.instance.syncNow();
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                  }
                },
              ),
            ),
          ),
          _Tile(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            subtitle: 'The music on this phone stays. Sign in again to use JARX.',
            onTap: () async {
              if (await _confirm(context, 'Sign out?',
                  'You will need to sign in again to use JARX.', 'Sign out')) {
                await Account.instance.signOut();
              }
            },
          ),
          _Tile(
            icon: Icons.delete_forever_rounded,
            color: Colors.redAccent,
            title: 'Delete my account',
            subtitle: 'Removes your account and everything JARX keeps about '
                'you on its server.',
            onTap: () async {
              if (!await _confirm(
                  context,
                  'Delete your JARX account?',
                  'Your account, synced music and learned taste are removed '
                      'from the JARX server. This cannot be undone. The music '
                      'on this phone stays.',
                  'Delete')) {
                return;
              }
              final error = await Account.instance.deleteAccount();
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
            },
          ),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            subtitle: 'What JARX keeps about you and why.',
            onTap: () => launchUrl(Uri.parse(jarxPrivacyUrl),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final ago = DateTime.now().difference(t);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  static Future<bool> _confirm(
      BuildContext context, String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action,
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Default_Theme.primaryColor1;
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: c),
        title: Text(title,
            style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
                color: Default_Theme.primaryColor1.withValues(alpha: 0.6))),
        onTap: onTap,
      ),
    );
  }
}
