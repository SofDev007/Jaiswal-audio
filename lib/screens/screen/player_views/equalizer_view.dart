import 'dart:async';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/screen/home_views/setting_views/custom_switch.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/player/eq_profiles.dart';
import 'package:Bloomee/services/player/output_route.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:ui' as ui;

const Map<String, List<double>> _kPresets = {
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Acoustic': [3, 2, 1, 0, 0, 0, 1, 2, 2, 3],
  'Bass Boost': [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  'Bass Reducer': [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0],
  'Classical': [0, 0, 0, 0, 0, 0, -1, -2, -3, -4],
  'Dance': [5, 4, 2, 0, 0, -1, -1, 0, 1, 2],
  'Deep': [4, 3, 2, 1, 0, 0, 1, 2, 3, 4],
  'EDM': [4, 3, 1, 0, -1, 1, 0, 1, 3, 4],
  'Electronic': [4, 3, 1, 0, -2, 2, 0, 1, 3, 4],
  'Hip-Hop': [5, 4, 1, 0, -1, -1, 0, 1, 2, 3],
  'Jazz': [2, 1, 0, -1, -1, 0, 1, 2, 3, 3],
  'Latin': [3, 2, 0, 0, -1, -1, -1, 0, 2, 3],
  'Live': [2, 1, 0, 1, 1, 2, 2, 1, 0, 0],
  'Lounge': [2, 1, 0, 0, 0, 0, 0, 0, 1, 2],
  'Metal': [4, 3, 0, -1, 1, 0, 1, 0, 2, 3],
  'Piano': [1, 1, 0, 2, 3, 3, 2, 1, 0, 0],
  'Pop': [-1, 2, 4, 4, 2, 0, -1, -1, 2, 3],
  'R&B': [3, 2, 1, 0, -1, 0, 1, 2, 2, 3],
  'Rock': [4, 3, 1, 0, -1, -1, 0, 2, 3, 4],
  'Small Speakers': [5, 4, 3, 2, 1, 0, -1, -2, -3, -4],
  'Spoken Word': [-3, -2, -1, 2, 4, 4, 2, 0, -1, -2],
  'Treble Boost': [0, 0, 0, 0, 0, 0, 2, 4, 5, 6],
  'Treble Reducer': [0, 0, 0, 0, 0, 0, -2, -4, -5, -6],
  'Vocal Booster': [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
};

class EqualizerView extends StatefulWidget {
  const EqualizerView({super.key});

  @override
  State<EqualizerView> createState() => _EqualizerViewState();
}

class _EqualizerViewState extends State<EqualizerView>
    with TickerProviderStateMixin {
  late PlayerEngine _engine;
  late SettingsCubit _settingsCubit;

  late List<double> _currentGains;
  late List<double> _animStartGains;
  String _selectedPreset = 'Flat';

  /// Curves the user saved under a name, shown before the built-in presets.
  List<EqProfile> _profiles = const [];

  // FIX H-01: EQ source (builtin vs device) state
  late String _eqSource;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _curveCtrl;
  late Animation<double> _curveAnim;

  static const double _minGain = -15;
  static const double _maxGain = 15;
  static const double _graphHeight = 280.0;

  int? _draggingBandIndex;
  bool _isGraphInteractive = false;

  // FIX L-01: Reactive subscriptions so the view stays in sync with engine state
  // changes from external code (settings restore, revive, Bloomee settings page).
  StreamSubscription? _eqEnabledSub;
  StreamSubscription? _eqGainsSub;

  @override
  void initState() {
    super.initState();
    _engine = context.read<BloomeePlayerCubit>().bloomeePlayer.engine;
    _settingsCubit = context.read<SettingsCubit>();

    _eqSource = _settingsCubit.state.eqSource;

    _currentGains =
        _engine.equalizerBands.map((b) => b.gain).toList(growable: false);
    _animStartGains = List.filled(_currentGains.length, 0.0);

    _loadProfiles();
    _selectedPreset = _settingsCubit.state.eqPreset;
    if (_selectedPreset != _matchingPreset()) {
      _selectedPreset = _matchingPreset();
    }

    // FIX L-01: Subscribe to reactive EQ streams so band gains and enabled
    // state are always in sync even if changed from another code path.
    _eqEnabledSub = _engine.equalizerEnabledStream.listen((enabled) {
      if (mounted) setState(() {});
    });
    _eqGainsSub = _engine.equalizerBandGainsStream.listen((gains) {
      if (mounted && !_draggingBandIndex.isNotNull) {
        setState(() {
          _animStartGains = List.from(_currentGains);
          _currentGains = List.from(gains);
          _selectedPreset = _matchingPreset();
        });
      }
    });

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _curveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _curveAnim =
        CurvedAnimation(parent: _curveCtrl, curve: Curves.easeOutCubic);
    _curveCtrl.forward();
  }

  @override
  void dispose() {
    _eqEnabledSub?.cancel();
    _eqGainsSub?.cancel();
    _settingsCubit.setEqBandGains(List<double>.from(_currentGains));
    _settingsCubit.setEqPreset(_selectedPreset);
    _fadeCtrl.dispose();
    _curveCtrl.dispose();
    super.dispose();
  }

  void _onBandChanged(int index, double value) {
    setState(() {
      _currentGains[index] = value;
      _animStartGains[index] = value;
      _selectedPreset = _matchingPreset();
    });
    // Engine update skipped during active drag to prevent audio stutter
  }

  void _onBandChangeEnd(int index) {
    _engine.setEqualizerBandGain(index, _currentGains[index], immediate: true);
    _settingsCubit.setEqBandGains(List<double>.from(_currentGains));
    _settingsCubit.setEqPreset(_selectedPreset);
  }

  void _applyPreset(String name) {
    final values = _profileGains(name) ?? _kPresets[name];
    if (values == null) return;

    HapticFeedback.lightImpact();

    setState(() {
      _selectedPreset = name;
      _animStartGains = List.from(_currentGains);
      for (var i = 0; i < _currentGains.length && i < values.length; i++) {
        _currentGains[i] = values[i];
      }
    });

    _curveCtrl.forward(from: 0);
    _engine.setEqualizerBandGains(_currentGains, immediate: true);
    _settingsCubit.setEqBandGains(List<double>.from(_currentGains));
    _settingsCubit.setEqPreset(name);
  }

  void _resetEQ() {
    HapticFeedback.mediumImpact();
    _engine.resetEqualizer();
    setState(() {
      _animStartGains = List.from(_currentGains);
      for (var i = 0; i < _currentGains.length; i++) {
        _currentGains[i] = 0;
      }
      _selectedPreset = 'Flat';
    });

    _curveCtrl.forward(from: 0);
    _settingsCubit.setEqBandGains(List<double>.from(_currentGains));
    _settingsCubit.setEqPreset('Flat');
  }

  /// FIX H-01: Toggle EQ source between 'builtin' and 'device'.
  void _setEqSource(String source) {
    HapticFeedback.lightImpact();
    setState(() => _eqSource = source);
    _settingsCubit.setEqSource(source);

    if (source == EqSourceValues.device) {
      // Disable in-app EQ so audio passes through to the device system EQ.
      _engine.setEqualizerEnabled(false);
      _settingsCubit.setEqEnabled(false);
    } else {
      // Restore in-app EQ to its last saved enabled state.
      final savedEnabled = _settingsCubit.state.eqEnabled;
      _engine.setEqualizerEnabled(savedEnabled);
    }
  }

  // ── Saved profiles ──────────────────────────────────────────────────────

  List<double>? _profileGains(String name) {
    for (final p in _profiles) {
      if (p.name == name) return p.gains;
    }
    return null;
  }

  bool _sameCurve(List<double> gains) {
    for (var i = 0; i < _currentGains.length && i < gains.length; i++) {
      if ((_currentGains[i] - gains[i]).abs() > 0.5) return false;
    }
    return true;
  }

  Future<void> _loadProfiles() async {
    final raw = await SettingsDAO(DBProvider.db)
        .getSettingStr(SettingKeys.eqCustomProfiles);
    if (!mounted) return;
    setState(() {
      _profiles = decodeEqProfiles(raw);
      _selectedPreset = _matchingPreset();
    });
  }

  Future<void> _storeProfiles(List<EqProfile> profiles) async {
    setState(() => _profiles = profiles);
    await SettingsDAO(DBProvider.db).putSettingStr(
        SettingKeys.eqCustomProfiles, encodeEqProfiles(profiles));
  }

  /// Names in use other than [except]: presets and other saved profiles.
  List<String> _takenNames({String? except}) => [
        ..._kPresets.keys,
        for (final p in _profiles)
          if (p.name != except) p.name,
      ];

  Future<void> _saveProfile() async {
    var n = _profiles.length + 1;
    while (_takenNames().contains('My EQ $n')) {
      n++;
    }
    final name = await _askName(
        title: 'Save equalizer', initial: 'My EQ $n', action: 'Save');
    if (name == null) return;
    HapticFeedback.lightImpact();
    await _storeProfiles(
        [..._profiles, (name: name, gains: List<double>.from(_currentGains))]);
    setState(() => _selectedPreset = name);
    _settingsCubit.setEqPreset(name);
  }

  Future<void> _renameProfile(String old) async {
    final name =
        await _askName(title: 'Rename', initial: old, action: 'Rename', except: old);
    if (name == null || name == old) return;
    await _storeProfiles([
      for (final p in _profiles)
        p.name == old ? (name: name, gains: p.gains) : p,
    ]);
    if (_selectedPreset == old) {
      setState(() => _selectedPreset = name);
      _settingsCubit.setEqPreset(name);
    }
  }

  Future<void> _deleteProfile(String name) async {
    await _storeProfiles([
      for (final p in _profiles)
        if (p.name != name) p,
    ]);
    setState(() => _selectedPreset = _matchingPreset());
    _settingsCubit.setEqPreset(_selectedPreset);
  }

  void _showProfileMenu(String name) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Default_Theme.themeColor,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white),
              title: const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheet);
                _renameProfile(name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Default_Theme.accentColor2),
              title: const Text('Delete',
                  style: TextStyle(color: Default_Theme.accentColor2)),
              onTap: () {
                Navigator.pop(sheet);
                _deleteProfile(name);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Asks for a profile name; null when cancelled.
  Future<String?> _askName(
      {required String title,
      required String initial,
      required String action,
      String? except}) {
    final controller = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialog) {
          void submit() {
            final e = eqProfileNameError(
                controller.text, _takenNames(except: except));
            if (e != null) {
              setDialog(() => error = e);
              return;
            }
            Navigator.pop(dialog, controller.text.trim());
          }

          return AlertDialog(
            backgroundColor: Default_Theme.themeColor,
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              style: const TextStyle(color: Colors.white),
              cursorColor: Default_Theme.accentColor2,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                errorText: error,
                counterStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3))),
                focusedBorder: const UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Default_Theme.accentColor2)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text('Cancel',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ),
              TextButton(
                onPressed: submit,
                child: Text(action,
                    style: const TextStyle(color: Default_Theme.accentColor2)),
              ),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  String _matchingPreset() {
    for (final p in _profiles) {
      if (_sameCurve(p.gains)) return p.name;
    }
    for (final entry in _kPresets.entries) {
      bool match = true;
      for (var i = 0; i < _currentGains.length && i < entry.value.length; i++) {
        if ((_currentGains[i] - entry.value[i]).abs() > 0.5) {
          match = false;
          break;
        }
      }
      if (match) return entry.key;
    }
    return 'Custom';
  }

  String _freqLabel(double hz) {
    if (hz >= 1000) {
      double k = hz / 1000;
      return '${k == k.toInt() ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return hz.toInt().toString();
  }

  void _handleGraphPanStart(
      DragDownDetails details, BoxConstraints constraints) {
    if (!_engine.equalizerEnabled) return;
    _updateDragInteraction(details.localPosition, constraints.maxWidth);
  }

  void _handleGraphPanUpdate(
      DragUpdateDetails details, BoxConstraints constraints) {
    if (!_engine.equalizerEnabled) return;
    _updateDragInteraction(details.localPosition, constraints.maxWidth);
  }

  void _updateDragInteraction(Offset localPosition, double width) {
    final N = _currentGains.length;
    final bandWidth = width / (N > 1 ? N - 1 : 1);
    final index = (localPosition.dx / bandWidth).round().clamp(0, N - 1);

    if (_draggingBandIndex != index) {
      if (_draggingBandIndex != null) _onBandChangeEnd(_draggingBandIndex!);
      setState(() => _draggingBandIndex = index);
    }
    _updateGainFromPan(localPosition.dy);
  }

  void _updateGainFromPan(double localY) {
    const topPad = 30.0;
    const bottomPad = 50.0;
    const availableHeight = _graphHeight - topPad - bottomPad;

    double fraction = 1.0 - ((localY - topPad) / availableHeight);
    fraction = fraction.clamp(0.0, 1.0);
    double newGain = _minGain + fraction * (_maxGain - _minGain);

    if (newGain.abs() < 0.6) {
      if (_currentGains[_draggingBandIndex!] != 0.0) {
        HapticFeedback.selectionClick();
      }
      newGain = 0.0;
    }

    _onBandChanged(_draggingBandIndex!, newGain);
  }

  void _handleGraphPanEnd(DragEndDetails details) {
    if (_draggingBandIndex != null) {
      _onBandChangeEnd(_draggingBandIndex!);
      setState(() => _draggingBandIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bands = _engine.equalizerBands;
    final isEnabled = _engine.equalizerEnabled;
    final isBuiltinMode = _eqSource == EqSourceValues.builtin;
    const accent = Default_Theme.accentColor2;

    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.eqTitle,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          if (isBuiltinMode)
            IconButton(
              icon: Icon(Icons.refresh_rounded,
                  color: Colors.white.withValues(alpha: 0.8), size: 22),
              onPressed: _resetEQ,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              physics: _isGraphInteractive
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // FIX H-01: EQ Source selection — 'Built-in' or 'Device'
                  _buildSectionHeader('EQ SOURCE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            Default_Theme.primaryColor1.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Default_Theme.primaryColor1
                                .withValues(alpha: 0.05)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _EqSourceOption(
                                  label: 'Built-in EQ',
                                  subtitle: '10-band in-app equalizer',
                                  isSelected:
                                      _eqSource == EqSourceValues.builtin,
                                  onTap: () =>
                                      _setEqSource(EqSourceValues.builtin),
                                  accent: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _EqSourceOption(
                                  label: 'Device EQ',
                                  subtitle: 'System / Dolby Atmos',
                                  isSelected:
                                      _eqSource == EqSourceValues.device,
                                  onTap: () =>
                                      _setEqSource(EqSourceValues.device),
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),
                          if (_eqSource == EqSourceValues.device) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: accent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'In-app EQ is disabled. Configure your device EQ in:\nSettings → Sound & Vibration → Equalizer',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                          fontSize: 12,
                                          height: 1.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Only show built-in EQ controls when in builtin mode
                  if (isBuiltinMode) ...[
                    StreamBuilder<bool>(
                      stream: OutputRoute.phoneSpeaker,
                      initialData: OutputRoute.phoneSpeaker.value,
                      builder: (context, snap) => snap.data != true
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.headphones_rounded,
                                        color: accent, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Paused on the phone speaker, where it only distorts the sound. It turns on by itself with headphones or Bluetooth.',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.75),
                                            fontSize: 12.5,
                                            height: 1.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    _buildSectionHeader('PRESETS'),
                    _buildPresetTabs(accent),
                    const SizedBox(height: 32),
                    _buildSectionHeader('CUSTOM CURVE'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Default_Theme.primaryColor1
                              .withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Default_Theme.primaryColor1
                                  .withValues(alpha: 0.05)),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.eqTitle,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.95),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                BloomeeSwitch(
                                  value: isEnabled,
                                  onChanged: () {
                                    _engine.setEqualizerEnabled(!isEnabled);
                                    _settingsCubit.setEqEnabled(!isEnabled);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            AnimatedOpacity(
                              opacity: isEnabled ? 1.0 : 0.3,
                              duration: const Duration(milliseconds: 300),
                              child: SizedBox(
                                height: _graphHeight,
                                child: Listener(
                                  onPointerDown: (_) => isEnabled
                                      ? setState(
                                          () => _isGraphInteractive = true)
                                      : null,
                                  onPointerUp: (_) => setState(
                                      () => _isGraphInteractive = false),
                                  onPointerCancel: (_) => setState(
                                      () => _isGraphInteractive = false),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanDown: (d) => _handleGraphPanStart(
                                            d, constraints),
                                        onPanUpdate: (d) =>
                                            _handleGraphPanUpdate(
                                                d, constraints),
                                        onPanEnd: _handleGraphPanEnd,
                                        onPanCancel: () => setState(
                                            () => _draggingBandIndex = null),
                                        child: AnimatedBuilder(
                                          animation: _curveAnim,
                                          builder: (context, _) => CustomPaint(
                                            size: Size(constraints.maxWidth,
                                                constraints.maxHeight),
                                            painter: _InteractiveEQPainter(
                                              startGains: _animStartGains,
                                              targetGains: _currentGains,
                                              minGain: _minGain,
                                              maxGain: _maxGain,
                                              accentColor: accent,
                                              animValue: _curveAnim.value,
                                              frequencies: bands
                                                  .map((b) => _freqLabel(
                                                      b.centerFrequency))
                                                  .toList(),
                                              draggingIndex: _draggingBandIndex,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 12),
      child: Text(title,
          style: TextStyle(
              color: Default_Theme.primaryColor2.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2)),
    );
  }

  Widget _buildSaveChip(Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saveProfile,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: accent),
              const SizedBox(width: 4),
              Text('Save',
                  style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetTabs(Color accent) {
    // The Save chip, then saved profiles (long-press to rename or delete),
    // then the built-in presets.
    final names = [for (final p in _profiles) p.name, ..._kPresets.keys];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: names.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) return _buildSaveChip(accent);
          final name = names[index - 1];
          final isSaved = index - 1 < _profiles.length;
          final isActive = name == _selectedPreset;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _applyPreset(name),
              onLongPress: isSaved ? () => _showProfileMenu(name) : null,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? accent.withValues(alpha: 0.15)
                      : Default_Theme.primaryColor1.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: isActive
                          ? accent.withValues(alpha: 0.5)
                          : Default_Theme.primaryColor1
                              .withValues(alpha: 0.05)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSaved) ...[
                      Icon(Icons.bookmark_rounded,
                          size: 14,
                          color: isActive
                              ? accent
                              : Default_Theme.primaryColor1
                                  .withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                    ],
                    Text(name,
                        style: TextStyle(
                            color: isActive
                                ? accent
                                : Default_Theme.primaryColor1
                                    .withValues(alpha: 0.75),
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A tappable EQ source option card.
class _EqSourceOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Color accent;

  const _EqSourceOption({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? accent
                          : Colors.white.withValues(alpha: 0.3),
                      width: isSelected ? 4 : 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? accent
                        : Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper extension used in EqualizerView
extension _NullableIntExt on int? {
  bool get isNotNull => this != null;
}

class _InteractiveEQPainter extends CustomPainter {
  final List<double> startGains;
  final List<double> targetGains;
  final double minGain;
  final double maxGain;
  final Color accentColor;
  final double animValue;
  final List<String> frequencies;
  final int? draggingIndex;

  _InteractiveEQPainter({
    required this.startGains,
    required this.targetGains,
    required this.minGain,
    required this.maxGain,
    required this.accentColor,
    required this.animValue,
    required this.frequencies,
    this.draggingIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final N = targetGains.length;
    if (N == 0) return;

    const topPad = 30.0;
    const bottomPad = 44.0;
    final availableHeight = h - topPad - bottomPad;
    final zeroY = topPad + availableHeight / 2;

    canvas.drawLine(Offset(0, zeroY), Offset(w, zeroY),
        Paint()..color = Colors.white.withValues(alpha: 0.08));

    final points = <Offset>[];
    for (var i = 0; i < N; i++) {
      final x = w * i / (N > 1 ? N - 1 : 1);
      final currentGain =
          ui.lerpDouble(startGains[i], targetGains[i], animValue) ?? 0.0;
      final normalized = 1.0 - ((currentGain - minGain) / (maxGain - minGain));
      points.add(
          Offset(x, topPad + (normalized.clamp(0.0, 1.0) * availableHeight)));
    }

    final curvePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];
      curvePath.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
          p2.dx,
          p2.dy);
    }

    final fillPath = Path.from(curvePath)
      ..lineTo(w, h - bottomPad)
      ..lineTo(0, h - bottomPad)
      ..close();
    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = ui.Gradient.linear(
              const Offset(0, topPad), Offset(0, h - bottomPad), [
            accentColor.withValues(alpha: 0.12),
            accentColor.withValues(alpha: 0.0)
          ]));
    canvas.drawPath(
        curvePath,
        Paint()
          ..color = accentColor
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    for (var i = 0; i < N; i++) {
      final isDragging = i == draggingIndex;
      canvas.drawCircle(points[i], isDragging ? 10.0 : 8.5,
          Paint()..color = Default_Theme.themeColor);
      canvas.drawCircle(
          points[i],
          isDragging ? 8.0 : 6.5,
          Paint()
            ..color = accentColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
      if (isDragging) {
        canvas.drawCircle(points[i], 3.0, Paint()..color = accentColor);
      }

      final tp = TextPainter(
          text: TextSpan(
              text: frequencies[i],
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(
          canvas, Offset(points[i].dx - (tp.width / 2), h - bottomPad + 14));
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveEQPainter old) =>
      old.animValue != animValue ||
      old.targetGains != targetGains ||
      old.draggingIndex != draggingIndex;
}
