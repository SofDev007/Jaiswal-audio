// Live audio visualizer for the Pulse card on Home. Android's Visualizer reads
// JARX's own audio session (MainActivity, channel "jarx/visualizer"); Android
// requires the microphone permission for that, asked once. Without it the
// card keeps its heartbeat line ([fallback]).
//
// Self-contained so it can be removed in one step: this file, its use in
// home_rows.dart, the channel in MainActivity.kt and the two permissions in
// AndroidManifest.xml.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

enum VisualizerStyle { line, bars, mirrored }

/// The latest waveform and spectrum from Android, smoothed for drawing.
class VisualizerFrame extends ChangeNotifier {
  static const points = 48;
  final wave = Float64List(points); // -1..1 per point
  final bands = Float64List(24); // 0..1, bass to treble
  final levels = Float64List(32); // 0..1 loudness per slice

  /// Unsigned 8-bit samples, 128 = silence.
  void addWave(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final step = bytes.length / points;
    for (var i = 0; i < points; i++) {
      final v = (bytes[(i * step).floor()] - 128) / 128;
      wave[i] += (v - wave[i]) * 0.6;
    }
    final slice = bytes.length / levels.length;
    for (var i = 0; i < levels.length; i++) {
      var sum = 0.0;
      final from = (i * slice).floor(), to = ((i + 1) * slice).floor();
      for (var j = from; j < to; j++) {
        final v = (bytes[j] - 128) / 128;
        sum += v * v;
      }
      final rms = sqrt(sum / max(1, to - from));
      final target = (rms * 3).clamp(0.0, 1.0);
      levels[i] = target > levels[i] ? target : levels[i] * 0.85;
    }
    notifyListeners();
  }

  /// Android FFT bytes: [0] DC, [1] Nyquist, then signed (re, im) pairs.
  void addFft(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    if (n < 4) return;
    final data = Int8List.sublistView(bytes);
    for (var b = 0; b < bands.length; b++) {
      // Log-spaced bins, so bass and treble get a fair share of bars.
      final lo = max(1, pow(n, b / bands.length).floor());
      final hi = max(lo + 1, pow(n, (b + 1) / bands.length).floor());
      var peak = 0.0;
      for (var k = lo; k < hi && k < n; k++) {
        final re = data[2 * k].toDouble(), im = data[2 * k + 1].toDouble();
        peak = max(peak, sqrt(re * re + im * im));
      }
      final target = (log(1 + peak) / log(1 + 128)).clamp(0.0, 1.0);
      bands[b] = target > bands[b] ? target : bands[b] * 0.8;
    }
    notifyListeners();
  }
}

/// Shows the live visualizer while [trackId] is playing and the visualizer
/// is allowed; otherwise [fallback]. Tap to try the next style (temporary,
/// until one style is chosen).
class LivePulseVisualizer extends StatefulWidget {
  const LivePulseVisualizer(
      {super.key, required this.trackId, required this.fallback});
  final String trackId;
  final Widget fallback;

  @override
  State<LivePulseVisualizer> createState() => _LivePulseVisualizerState();
}

class _LivePulseVisualizerState extends State<LivePulseVisualizer> {
  static const _channel = EventChannel('jarx/visualizer');
  static const _askedKey = 'visualizerPermissionAsked';
  static VisualizerStyle _style = VisualizerStyle.line;

  late final _player = context.read<BloomeePlayerCubit>().bloomeePlayer;
  late final StreamSubscription<bool> _playingSub;
  StreamSubscription? _frames;
  final _frame = VisualizerFrame();
  bool _live = false;
  bool _showName = false;
  Timer? _nameTimer;

  @override
  void initState() {
    super.initState();
    _playingSub = _player.engine.playingStream.listen((playing) {
      final mine = playing && _player.currentMedia.id == widget.trackId;
      mine ? _start() : _stop();
    });
  }

  Future<void> _start() async {
    if (_frames != null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (!await _allowed()) return;
    final session = await _player.engine.audioSessionId;
    if (session == null || !mounted) return;
    _frames = _channel.receiveBroadcastStream(session).listen((e) {
      final m = e as Map;
      final wave = m['wave'], fft = m['fft'];
      if (wave is Uint8List) _frame.addWave(wave);
      if (fft is Uint8List) _frame.addFft(fft);
      if (!_live && mounted) setState(() => _live = true);
    }, onError: (_) => _stop());
  }

  void _stop() {
    _frames?.cancel();
    _frames = null;
    if (_live && mounted) setState(() => _live = false);
  }

  /// Microphone permission (Android's name for what Visualizer needs).
  /// Explained and asked once; after that only checked.
  Future<bool> _allowed() async {
    if (await Permission.microphone.isGranted) return true;
    final settings = SettingsDAO(DBProvider.db);
    if (await settings.getSettingBool(_askedKey) == true) return false;
    await settings.putSettingBool(_askedKey, true);
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: Default_Theme.themeColor,
        title: const Text('Live visualizer',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'To draw the wave from the music itself, Android needs the '
          '"Microphone" permission. JARX only reads its own music output and '
          'never uses the microphone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text('Not now',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Continue',
                style: TextStyle(color: Default_Theme.accentColor2)),
          ),
        ],
      ),
    );
    if (go != true) return false;
    return (await Permission.microphone.request()).isGranted;
  }

  void _nextStyle() {
    setState(() {
      _style = VisualizerStyle
          .values[(_style.index + 1) % VisualizerStyle.values.length];
      _showName = true;
    });
    _nameTimer?.cancel();
    _nameTimer = Timer(const Duration(milliseconds: 1400),
        () => mounted ? setState(() => _showName = false) : null);
  }

  @override
  void dispose() {
    _playingSub.cancel();
    _frames?.cancel();
    _nameTimer?.cancel();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_live) return widget.fallback;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _nextStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: VisualizerPainter(_frame, _style)),
          if (_showName)
            Align(
              alignment: Alignment.topRight,
              child: Text(
                const {
                  VisualizerStyle.line: 'Line',
                  VisualizerStyle.bars: 'Bars',
                  VisualizerStyle.mirrored: 'Mirrored',
                }[_style]!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class VisualizerPainter extends CustomPainter {
  VisualizerPainter(this.frame, this.style) : super(repaint: frame);
  final VisualizerFrame frame;
  final VisualizerStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Default_Theme.accentColor2.withValues(alpha: 0.9)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final mid = size.height / 2;
    switch (style) {
      case VisualizerStyle.line:
        final w = frame.wave;
        final dx = size.width / (w.length - 1);
        final path = Path()..moveTo(0, mid - w[0] * mid);
        for (var i = 1; i < w.length; i++) {
          path.lineTo(i * dx, mid - (w[i] * 1.6).clamp(-1.0, 1.0) * mid);
        }
        canvas.drawPath(
            path,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      case VisualizerStyle.bars:
        final b = frame.bands;
        final slot = size.width / b.length;
        paint.strokeWidth = slot * 0.55;
        for (var i = 0; i < b.length; i++) {
          final h = max(2.0, b[i] * size.height);
          final x = (i + 0.5) * slot;
          canvas.drawLine(
              Offset(x, size.height), Offset(x, size.height - h), paint);
        }
      case VisualizerStyle.mirrored:
        final l = frame.levels;
        final slot = size.width / l.length;
        paint.strokeWidth = slot * 0.6;
        for (var i = 0; i < l.length; i++) {
          final h = max(1.5, l[i] * mid);
          final x = (i + 0.5) * slot;
          canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
        }
    }
  }

  @override
  bool shouldRepaint(VisualizerPainter old) => old.style != style;
}
