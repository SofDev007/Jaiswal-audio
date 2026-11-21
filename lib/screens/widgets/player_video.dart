// Video mode on the player screen: "Play video" turns the cover into the
// song's music video. The video is muted and kept in time with the song:
// the sound stays JARX's own player (equalizer, crossfade, cache all work).
// It plays inside JARX, never sends the user to YouTube, and only while the
// player screen is open. Quality and full screen (landscape) on the video.

import 'dart:async';
import 'dart:io';

import 'package:Bloomee/screens/widgets/tip_overlay.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/models/exported.dart' show Track;
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/screens/widgets/gradient_progress_bar.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:Bloomee/services/player/video_streams.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class PlayerVideo {
  /// Video mode is on (until turned off; stays on between songs).
  static final open = ValueNotifier<bool>(false);

  /// The video on screen now. Full screen shows this one, so it carries on
  /// into the next song's video and follows a new quality.
  static final current = ValueNotifier<VideoNow?>(null);

  /// The chosen quality: a picture height, or 0 for Auto. Remembered.
  static int? _height;

  static Future<int> chosenHeight() async =>
      _height ??= int.tryParse(await SettingsDAO(DBProvider.db)
                  .getSettingStr(SettingKeys.videoQuality) ??
              '') ??
          0;

  static Future<void> choose(int height) async {
    _height = height;
    await SettingsDAO(DBProvider.db)
        .putSettingStr(SettingKeys.videoQuality, '$height');
  }

  /// Full-screen captions: the language last picked, [captionsOff], or ''
  /// (never picked: on, in English or Hindi when the video has them).
  static final captions = ValueNotifier<String>('');

  /// Full-screen caption size: small, medium or large.
  static final captionSize = ValueNotifier<String>('medium');
  static bool _captionPrefsRead = false;

  static Future<void> readCaptionPrefs() async {
    if (_captionPrefsRead) return;
    _captionPrefsRead = true;
    final dao = SettingsDAO(DBProvider.db);
    captions.value = await dao.getSettingStr(SettingKeys.videoCaptions) ?? '';
    captionSize.value =
        await dao.getSettingStr(SettingKeys.videoCaptionSize) ?? 'medium';
  }

  static void setCaptions(String language) {
    captions.value = language;
    SettingsDAO(DBProvider.db)
        .putSettingStr(SettingKeys.videoCaptions, language);
  }

  static void setCaptionSize(String size) {
    captionSize.value = size;
    SettingsDAO(DBProvider.db)
        .putSettingStr(SettingKeys.videoCaptionSize, size);
  }
}

/// The video on screen now, for full screen: its player, its qualities and
/// caption tracks, and how to switch quality.
class VideoNow {
  const VideoNow(this.controller, this.source, this.want, this.chooseQuality);
  final VideoPlayerController controller;
  final VideoSource source;

  /// The quality playing: a height, or 0 for Auto.
  final int want;
  final void Function(int height) chooseQuality;
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
                  scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
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
  static const _app = MethodChannel('jarx/app');

  VideoPlayerController? _c;
  VideoSource? _source;
  String? _error;
  Timer? _sync;

  /// The player screen is open and JARX is on screen: only then does the
  /// picture play (and download). It stays paused behind the mini player,
  /// on other screens and in the background.
  late bool _visible = context.read<PlayerOverlayCubit>().state;
  bool _resumed = WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _shown => _visible && _resumed;
  StreamSubscription<bool>? _overlaySub;
  AppLifecycleListener? _lifecycle;

  /// No catching up until then (just after a jump or a new quality).
  DateTime _settleUntil = DateTime(0);
  bool _screenOn = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
        onStateChange: (s) =>
            _setShown(resumed: s == AppLifecycleState.resumed));
    _overlaySub = context
        .read<PlayerOverlayCubit>()
        .stream
        .listen((v) => _setShown(visible: v));
    _load();
  }

  @override
  void dispose() {
    _sync?.cancel();
    _overlaySub?.cancel();
    _lifecycle?.dispose();
    _keepScreenOn(false);
    final c = _c;
    if (c != null && PlayerVideo.current.value?.controller == c) {
      // Full screen may still show it: let it move off first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (PlayerVideo.current.value?.controller == c) {
          PlayerVideo.current.value = null;
        }
        c.dispose();
      });
    } else {
      c?.dispose();
    }
    super.dispose();
  }

  void _setShown({bool? visible, bool? resumed}) {
    _visible = visible ?? _visible;
    _resumed = resumed ?? _resumed;
    _keepInTime();
  }

  PlayerEngine get _engine =>
      context.read<BloomeePlayerCubit>().bloomeePlayer.engine;

  Future<void> _load() async {
    try {
      final want = await PlayerVideo.chosenHeight();
      final source = _source ?? await videoSourceFor(widget.track);
      final streams = source.streams;
      if (!mounted) return;
      if (streams.isEmpty) {
        setState(() => _error = 'No video for this song.');
        return;
      }
      final pick = videoQualityFor(streams, want);
      final options = VideoPlayerOptions(mixWithOthers: true);
      final VideoPlayerController c;
      File? master;
      if (pick.first.hls) {
        // Only the chosen quality (or all of them for Auto), picture only.
        master = File('${(await getTemporaryDirectory()).path}/'
            'jarx_video_${DateTime.now().microsecondsSinceEpoch}.m3u8');
        await master.writeAsString(hlsMasterOf(pick));
        c = VideoPlayerController.file(master, videoPlayerOptions: options);
      } else {
        // Muted, and never takes the sound away from the song.
        c = VideoPlayerController.networkUrl(pick.single.url,
            httpHeaders: pick.single.headers ?? const {},
            videoPlayerOptions: options);
      }
      try {
        await c.initialize();
      } finally {
        // Read once when the video opens; not needed after.
        unawaited(master?.delete().then((_) {}, onError: (_) {}));
      }
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      // Start where the song is, then give it a moment before catching up.
      await c.seekTo(_engine.position);
      _settleUntil = DateTime.now().add(const Duration(seconds: 2));
      final old = _c;
      setState(() {
        _source = source;
        _c = c;
        _error = null;
      });
      PlayerVideo.current.value = VideoNow(c, source, want, (height) {
        PlayerVideo.choose(height);
        _load();
      });
      await old?.dispose();
      _keepInTime();
      _sync ??= Timer.periodic(
          const Duration(milliseconds: 500), (_) => _keepInTime());
    } on PluginNotLoadedException {
      if (mounted) {
        setState(() => _error =
            'Install the YouTube Video plugin (Settings › Plugins) to watch videos.');
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = "Couldn't load the video right now.");
    }
  }

  /// Follows the song: plays and pauses with it. A small gap is closed by
  /// playing the picture a little faster or slower (no jump, so it never
  /// freezes); only a big one (the song was moved, or the picture stalled)
  /// jumps, and then it settles for a moment before checking again.
  void _keepInTime() {
    final c = _c;
    if (!mounted || c == null || !c.value.isInitialized) return;
    final engine = _engine;
    final play = engine.playing && _shown;
    if (play != c.value.isPlaying) play ? c.play() : c.pause();
    _keepScreenOn(play);
    if (!play || c.value.isBuffering || DateTime.now().isBefore(_settleUntil)) {
      return;
    }
    final songAt = engine.position;
    final ahead = (c.value.position - songAt).inMilliseconds;
    if (ahead.abs() > 1000) {
      c.seekTo(songAt + const Duration(milliseconds: 400));
      _setSpeed(c, 1.0);
      _settleUntil = DateTime.now().add(const Duration(seconds: 3));
    } else {
      _setSpeed(
          c,
          ahead.abs() < 80
              ? 1.0
              : (1 - ahead / 2000).clamp(0.9, 1.1).toDouble());
    }
  }

  void _setSpeed(VideoPlayerController c, double speed) {
    if ((c.value.playbackSpeed - speed).abs() > 0.01) c.setPlaybackSpeed(speed);
  }

  /// The screen stays on while the video plays.
  void _keepScreenOn(bool on) {
    if (on == _screenOn) return;
    _screenOn = on;
    _app.invokeMethod('keepScreenOn', {'on': on}).then((_) {}, onError: (_) {});
  }

  void _chooseQuality() {
    final now = PlayerVideo.current.value;
    if (now != null && now.controller == _c) showVideoSettings(context, now);
  }

  void _fullScreen() {
    if (_c == null) return;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => const _FullScreenVideo(),
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
                _VideoButton(
                    Icons.settings_rounded, 'Video quality', _chooseQuality),
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

/// Video settings: the quality, and in full screen the captions and their
/// size. Quality closes the sheet; caption choices apply at once.
Future<void> showVideoSettings(BuildContext context, VideoNow now,
    {bool fullScreen = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Default_Theme.themeColor,
    constraints: BoxConstraints(
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheet) => _VideoSettings(now: now, fullScreen: fullScreen),
  );
}

class _VideoSettings extends StatelessWidget {
  const _VideoSettings({required this.now, required this.fullScreen});
  final VideoNow now;
  final bool fullScreen;

  static const _sizes = {
    'small': 'Small',
    'medium': 'Medium',
    'large': 'Large'
  };

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: const TextStyle(
                color: Default_Theme.primaryColor1,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
      );

  Widget _choice(String title, String? sub, bool on, VoidCallback onTap) =>
      ListTile(
        dense: true,
        title: Text(title,
            style: const TextStyle(
                color: Default_Theme.primaryColor1,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        subtitle: sub == null
            ? null
            : Text(sub,
                style: const TextStyle(
                    color: Default_Theme.primaryColor2, fontSize: 13)),
        trailing: on
            ? const Icon(Icons.check_rounded, color: Default_Theme.accentColor2)
            : null,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final streams = now.source.streams;
    final hls = streams.isNotEmpty && streams.first.hls;
    void quality(int height) {
      Navigator.pop(context);
      if (height != now.want) now.chooseQuality(height);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _heading('Video quality'),
        if (hls)
          _choice('Auto', 'Best for your connection, up to 1080p',
              now.want == 0, () => quality(0)),
        for (final s in streams.reversed)
          _choice(
            s.height >= 720 ? '${s.label} HD' : s.label,
            s.bandwidth > 0 ? 'About ${dataPerHour(s)} an hour' : null,
            now.want == s.height,
            () => quality(s.height),
          ),
        if (!hls)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
                'Update the YouTube Video plugin (Settings › Plugins) '
                'for up to 1080p.',
                style: TextStyle(color: Default_Theme.primaryColor2)),
          ),
        if (fullScreen) ...[
          const Divider(color: Colors.white12, height: 24),
          _heading('Captions'),
          ValueListenableBuilder<String>(
            valueListenable: PlayerVideo.captions,
            builder: (context, pref, _) {
              final tracks = now.source.captions;
              if (tracks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text('This video has no captions.',
                      style: TextStyle(color: Default_Theme.primaryColor2)),
                );
              }
              final showing = captionTrackFor(tracks, pref);
              return Column(children: [
                _choice('Off', null, showing == null,
                    () => PlayerVideo.setCaptions(captionsOff)),
                for (final t in tracks)
                  _choice(t.name, null, identical(showing, t),
                      () => PlayerVideo.setCaptions(t.language)),
              ]);
            },
          ),
          _heading('Caption size'),
          ValueListenableBuilder<String>(
            valueListenable: PlayerVideo.captionSize,
            builder: (context, size, _) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Wrap(spacing: 10, children: [
                for (final e in _sizes.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: size == e.key,
                    onSelected: (_) => PlayerVideo.setCaptionSize(e.key),
                    selectedColor: Default_Theme.accentColor2,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                        color: size == e.key
                            ? Colors.white
                            : Default_Theme.primaryColor1,
                        fontWeight: FontWeight.w600),
                    showCheckmark: false,
                  ),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

/// The current video, filling a landscape screen, with the song's controls
/// (tap to show or hide them) and the video's captions. It carries on into
/// the next song's video; Back returns to the player, and so does a next
/// song without a video.
class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo();

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  static const _captionFont = {'small': 16.0, 'medium': 20.0, 'large': 26.0};

  Timer? _leave;
  Timer? _hide;
  bool _controls = true;

  /// The captions showing, by their track's link.
  Uri? _captionUrl;
  List<Caption> _captions = const [];

  /// The language before captions were switched off, to switch back to.
  static String _beforeOff = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    PlayerVideo.current.addListener(_onVideo);
    PlayerVideo.captions.addListener(_loadCaptions);
    PlayerVideo.readCaptionPrefs().then((_) => _loadCaptions());
    _showControls();
  }

  @override
  void dispose() {
    _leave?.cancel();
    _hide?.cancel();
    PlayerVideo.current.removeListener(_onVideo);
    PlayerVideo.captions.removeListener(_loadCaptions);
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// A new video (next song or quality), or none for a while (the next song
  /// has none, or it couldn't load): then back to the player.
  void _onVideo() {
    _leave?.cancel();
    if (PlayerVideo.current.value == null) {
      _leave = Timer(const Duration(seconds: 6), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    _loadCaptions();
  }

  Future<void> _loadCaptions() async {
    final now = PlayerVideo.current.value;
    final track = now == null
        ? null
        : captionTrackFor(now.source.captions, PlayerVideo.captions.value);
    if (track?.url == _captionUrl) return;
    _captionUrl = track?.url;
    if (mounted) setState(() => _captions = const []);
    if (track == null) return;
    try {
      final captions = await captionsFor(track);
      if (mounted && _captionUrl == track.url) {
        setState(() => _captions = captions);
      }
    } catch (_) {
      // No captions this time.
    }
  }

  /// Shows the controls; they hide after a few seconds while playing.
  void _showControls() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final playing =
          context.read<BloomeePlayerCubit>().bloomeePlayer.engine.playing;
      playing ? setState(() => _controls = false) : _showControls();
    });
  }

  void _toggleControls() {
    if (_controls) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _showControls();
    }
  }

  void _toggleCaptions() {
    final pref = PlayerVideo.captions.value;
    if (pref == captionsOff) {
      PlayerVideo.setCaptions(_beforeOff);
    } else {
      _beforeOff = pref;
      PlayerVideo.setCaptions(captionsOff);
    }
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BloomeePlayerCubit>();
    final player = cubit.bloomeePlayer;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          Center(
            child: ValueListenableBuilder<VideoNow?>(
              valueListenable: PlayerVideo.current,
              builder: (context, now, _) => now == null
                  ? const CircularProgressIndicator(
                      color: Default_Theme.accentColor2)
                  : AspectRatio(
                      key: ObjectKey(now.controller),
                      aspectRatio: now.controller.value.aspectRatio,
                      child: VideoPlayer(now.controller)),
            ),
          ),

          // Captions, timed to the song; above the seek bar when it shows.
          StreamBuilder<ProgressBarStreams>(
            stream: cubit.progressStreams,
            builder: (context, snap) {
              final text =
                  captionAt(_captions, snap.data?.position ?? Duration.zero);
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                left: 56,
                right: 56,
                bottom: _controls ? 76 : 18,
                child: text.isEmpty
                    ? const SizedBox.shrink()
                    : Center(
                        child: ValueListenableBuilder<String>(
                          valueListenable: PlayerVideo.captionSize,
                          builder: (context, size, _) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(text,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: _captionFont[size] ?? 20,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
              );
            },
          ),

          // The controls.
          IgnorePointer(
            ignoring: !_controls,
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Stack(fit: StackFit.expand, children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black54
                      ],
                      stops: [0, 0.25, 0.7, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Row(children: [
                    _VideoButton(Icons.fullscreen_exit_rounded,
                        'Exit full screen', () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StreamBuilder<MediaItem?>(
                        stream: player.mediaItem,
                        builder: (context, s) => Text(
                          [s.data?.title, s.data?.artist]
                              .whereType<String>()
                              .where((t) => t.isNotEmpty)
                              .join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<VideoNow?>(
                      valueListenable: PlayerVideo.current,
                      builder: (context, now, _) =>
                          (now?.source.captions.isEmpty ?? true)
                              ? const SizedBox.shrink()
                              : ValueListenableBuilder<String>(
                                  valueListenable: PlayerVideo.captions,
                                  builder: (context, pref, _) => TipAnchor(
                                      id: 'T5',
                                      child: _VideoButton(
                                        pref == captionsOff
                                            ? Icons.closed_caption_off_outlined
                                            : Icons.closed_caption_rounded,
                                        pref == captionsOff
                                            ? 'Turn captions on'
                                            : 'Turn captions off',
                                        _toggleCaptions,
                                      )),
                                ),
                    ),
                    const SizedBox(width: 8),
                    _VideoButton(Icons.settings_rounded, 'Settings', () {
                      final now = PlayerVideo.current.value;
                      if (now == null) return;
                      _hide?.cancel();
                      showVideoSettings(context, now, fullScreen: true)
                          .whenComplete(() {
                        if (mounted) _showControls();
                      });
                    }),
                  ]),
                ),
                Center(
                  child: StreamBuilder<ProgressBarStreams>(
                    stream: cubit.progressStreams,
                    builder: (context, snap) {
                      final playing = snap.data?.isPlaying ?? false;
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        _BigButton(Icons.skip_previous_rounded, 40, () {
                          player.skipToPrevious();
                          _showControls();
                        }),
                        const SizedBox(width: 36),
                        _BigButton(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            56, () {
                          playing ? player.pause() : player.play();
                          _showControls();
                        }),
                        const SizedBox(width: 36),
                        _BigButton(Icons.skip_next_rounded, 40, () {
                          player.skipToNext();
                          _showControls();
                        }),
                      ]);
                    },
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 10,
                  child: StreamBuilder<ProgressBarStreams>(
                    stream: cubit.progressStreams,
                    builder: (context, snap) {
                      final data = snap.data;
                      return GradientProgressBar.fromAccentColors(
                        progress: data?.position ?? Duration.zero,
                        total: data?.duration ?? Duration.zero,
                        buffered: data?.buffered ?? Duration.zero,
                        onSeek: (to) {
                          player.seek(to);
                          _showControls();
                        },
                        isPlaying: data?.isPlaying ?? false,
                        activeAccentColor: Default_Theme.accentColor1,
                        inactiveAccentColor: Default_Theme.accentColor2,
                        trackHeight: 5.0,
                        thumbRadius: 7.0,
                        timeLabelLocation: TimeLabelLocation.sides,
                        timeLabelPadding: 10,
                        timeLabelStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        inactiveTrackColor: Colors.white24,
                        animationDuration: const Duration(milliseconds: 200),
                        animationCurve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton(this.icon, this.size, this.onTap);
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        iconSize: size,
        style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.35)),
        icon: Icon(icon, color: Colors.white),
      );
}
