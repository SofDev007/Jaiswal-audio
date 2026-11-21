// Your corner: opened by tapping your photo on Home. This month's listening
// (all your phones), your top 5 artists and songs, and a silly comparison.

import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/services/account/account.dart';
import 'package:Bloomee/services/player/listening_time.dart';
import 'package:Bloomee/services/your_corner.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The signed-in user's Google photo, or the first letter of their name
/// when there's no photo or it can't load (offline).
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Account.instance.state,
      builder: (context, state, _) {
        final user = state.user;
        final name = user?.name.trim() ?? '';
        final letter = Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [
              Default_Theme.accentColor1,
              Default_Theme.accentColor2
            ]),
          ),
          child: Text(name.isEmpty ? '♪' : name[0].toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.45)),
        );
        final photo = user?.photo ?? '';
        if (photo.isEmpty) return letter;
        return ClipOval(
          child: CachedNetworkImage(
            imageUrl: photo,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => letter,
            errorWidget: (_, __, ___) => letter,
          ),
        );
      },
    );
  }
}

class YourCornerView extends StatelessWidget {
  const YourCornerView({super.key});

  @override
  Widget build(BuildContext context) {
    final first = (Account.instance.user?.name.trim() ?? '').split(' ').first;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Default_Theme.themeColor,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Default_Theme.primaryColor1),
      ),
      body: FutureBuilder<ListeningStats>(
        future: ListeningTime.loadAllPhones(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: Default_Theme.accentColor2));
          }
          final now = DateTime.now();
          final month = cornerMonth(snap.data!, now);
          final stats = month.stats;
          final artists = stats.topArtists(5);
          final songs = stats.topSongs(5);
          final silly = sillyComparison(stats.totalMs ~/ 60000, now.day);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
            children: [
              Row(children: [
                const UserAvatar(size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.isEmpty ? 'Hi there' : 'Hi, $first',
                          style: const TextStyle(
                              color: Default_Theme.primaryColor1,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text('Your corner',
                          style: TextStyle(
                              color: Default_Theme.primaryColor2
                                  .withValues(alpha: 0.7),
                              fontSize: 15)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _Card(children: [
                Text('${month.label} so far',
                    style: TextStyle(
                        color:
                            Default_Theme.primaryColor2.withValues(alpha: 0.75),
                        fontSize: 14)),
                const SizedBox(height: 4),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => const LinearGradient(colors: [
                    Default_Theme.accentColor1light,
                    Default_Theme.accentColor2
                  ]).createShader(r),
                  child: Text(minutesText(stats.totalMs),
                      style: const TextStyle(
                          fontSize: 38, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                Text(
                    silly ??
                        'Your corner is empty this month. Play something and '
                            'it fills up.',
                    style: const TextStyle(
                        color: Default_Theme.primaryColor1,
                        fontSize: 15,
                        height: 1.35)),
              ]),
              if (artists.isNotEmpty) ...[
                _title('Your top 5 artists this month'),
                _Card(children: [
                  for (final (i, a) in artists.indexed)
                    _Row(
                      rank: i + 1,
                      title: a.name,
                      trailing: minutesText(a.ms),
                      share: a.ms / artists.first.ms,
                    ),
                ]),
              ],
              if (songs.isNotEmpty) ...[
                _title('Your top 5 songs this month'),
                _Card(children: [
                  for (final (i, s) in songs.indexed)
                    _Row(
                      rank: i + 1,
                      title: s.title,
                      subtitle: s.artist,
                      trailing: '${s.plays} ${s.plays == 1 ? 'play' : 'plays'}',
                    ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  static Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
        child: Text(t,
            style: const TextStyle(
                color: Default_Theme.primaryColor1,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rank,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.share,
  });
  final int rank;
  final String title, trailing;
  final String? subtitle;

  /// 0..1: a bar under the row (artists: time compared with the top one).
  final double? share;

  @override
  Widget build(BuildContext context) {
    final dim = Default_Theme.primaryColor2.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('$rank',
              style: TextStyle(
                  color: rank == 1 ? Default_Theme.accentColor2 : dim,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Default_Theme.primaryColor1,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dim, fontSize: 12.5)),
              if (share != null) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: share!.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: Default_Theme.accentColor1,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(trailing, style: TextStyle(color: dim, fontSize: 13)),
      ]),
    );
  }
}
