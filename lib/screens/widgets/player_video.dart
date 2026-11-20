// Video mode on the player screen: "Play video" turns the cover into the
// song's music video. The video is muted and kept in time with the song:
// the sound stays JARX's own player (equalizer, crossfade, cache all work).
// It plays inside JARX, never sends the user to YouTube, and only while the
// player screen is open. Quality and full screen (landscape) on the video.

import 'dart:async';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/exported.dart' show Track;
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/services/player/video_streams.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

class PlayerVideo {
  /// Video mode is on (until turned off; stays on between songs).
  static final open = ValueNotifier<bool>(false);

  /// The chosen picture height; 0 for the default (360p or the nearest).
  static int height = 0;
}

/// "Play video" / "Show cover", for YouTube songs, just above the title.
class PlayVideoButton extends StatelessWidget {
  const PlayVideoButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return StreamBuilder<MediaItem?>(
      stream: player.mediaItem,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: PlayerVideo.open,
        builder: (context, on, _) {
          final show = hasVideo(player.currentTrackInfo);
          return AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: !show
                ? const SizedBox(width: double.infinity)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Default_Theme.primaryColor1,
                          backgroundColor: on
                              ? Colors.white.withValues(alpha: 0.08)
                              : Default_Theme.accentColor2
                                  .withValues(alpha: 0.85),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => PlayerVideo.open.value = !on,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (c, a) =>
                              RotationTransition(turns: a, child: c),
                          child: Icon(
                              on
                                  ? Icons.album_rounded
                                  : Icons.ondemand_video_rounded,
                              key: ValueKey(on),
                              size: 18),
                        ),
                        label: Text(on ? 'Show cover' : 'Play video',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// The cover, or in video mode (YouTube songs) the video, which springs in.
class CoverOrVideo extends StatelessWidget {
  const CoverOrVideo({super.key, required this.cover});
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return StreamBuilder<MediaItem?>(
      stream: player.mediaItem,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: PlayerVideo.open,
        builder: (context, on, _) {
          final track = player.currentTrackInfo;
          final show = on && hasVideo(track);
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(a),
                  child: child),
            ),
            child: show
                ? MiniVideo(key: ValueKey('video-${track.id}'), track: track)
                : KeyedSubtree(key: const ValueKey('cover'), child: cover),
          );
        },
      ),
    );
  }
}

class MiniVideo extends StatefulWidget {
  const MiniVideo({super.key, required this.track});
  final Track track;

  @override
  State<MiniVideo> createState() => _MiniVideoState();
}

class _MiniVideoState extends State<MiniVideo> {
  VideoPlayerController? _c;
  List<VideoStream> _streams = const [];
  VideoStream? _current;
  String? _error;
  Timer? _sync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sync?.cancel();
    _c?.dispose();
    super.dispose();
  }

  Future<void> _load([VideoStream? pick]) async {
    try {
      final streams =
          _streams.isEmpty ? await videoStreamsFor(widget.track) : _streams;
      if (!mounted) return;
      if (streams.isEmpty) {
        setState(() => _error = 'No video for this song.');
        return;
      }
      final want = PlayerVideo.height == 0 ? 360 : PlayerVideo.height;
      final s = pick ??
          streams.firstWhere((s) => s.height >= want,
              orElse: () => streams.last);
      final c = VideoPlayerController.networkUrl(s.url,
          httpHeaders: s.headers ?? const {},
          // Muted, and never takes the sound away from the song.
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await c.initialize();
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      final old = _c;
      setState(() {
        _streams = streams;
        _current = s;
        _c = c;
        _error = null;
      });
      await old?.dispose();
      _keepInTime();
      _sync ??= Timer.periodic(
          const Duration(milliseconds: 700), (_) => _keepInTime());
    } on PluginNotLoadedException {
      if (mounted) {
        setState(() => _error =
            'Install the YouTube Video plugin (Settings › Plugins) to watch videos.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load the video right now.");
    }
  }

  /// Follows the song: plays and pauses with it, jumps when more than
  /// about half a second apart.
  void _keepInTime() {
    final c = _c;
    if (!mounted || c == null || !c.value.isInitialized) return;
    final engine = context.read<BloomeePlayerCubit>().bloomeePlayer.engine;
    if (engine.playing != c.value.isPlaying) {
      engine.playing ? c.play() : c.pause();
    }
    final drift = c.value.position - engine.position;
    if (drift.inMilliseconds.abs() > 450 && c.value.duration > Duration.zero) {
      c.seekTo(engine.position + const Duration(milliseconds: 150));
    }
  }

  void _chooseQuality() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Default_Theme.themeColor,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Video quality',
                style: TextStyle(
                    color: Default_Theme.primaryColor1,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          for (final s in _streams.reversed)
            ListTile(
              title: Text(s.label,
                  style: const TextStyle(color: Default_Theme.primaryColor1)),
              trailing: s == _current
                  ? const Icon(Icons.check_rounded,
                      color: Default_Theme.accentColor2)
                  : null,
              onTap: () {
                Navigator.pop(sheet);
                PlayerVideo.height = s.height;
                if (s != _current) _load(s);
              },
            ),
          if (_streams.length == 1)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                  'YouTube offers this video in one quality here.',
                  style: TextStyle(color: Default_Theme.primaryColor2)),
            ),
        ]),
      ),
    );
  }

  void _fullScreen() {
    final c = _c;
    if (c == null) return;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => _FullScreenVideo(controller: c),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Default_Theme.primaryColor2, fontSize: 15)),
      );
    } else if (c == null) {
      body = const CircularProgressIndicator(color: Default_Theme.accentColor2);
    } else {
      body = AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            VideoPlayer(c),
            Positioned(
              top: 4,
              right: 4,
              child: Row(children: [
                _VideoButton(Icons.settings_rounded, 'Video quality',
                    _chooseQuality),
                _VideoButton(
                    Icons.fullscreen_rounded, 'Full screen', _fullScreen),
              ]),
            ),
          ]),
        ),
      );
    }
    return Center(child: body);
  }
}

class _VideoButton extends StatelessWidget {
  const _VideoButton(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.45)),
        icon: Icon(icon, color: Colors.white, size: 22),
      );
}

/// The same video, filling a landscape screen. Back returns to the player.
class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: AspectRatio(
              aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _VideoButton(Icons.fullscreen_exit_rounded, 'Exit full screen',
              () => Navigator.of(context).pop()),
        ),
      ]),
    );
  }
}
