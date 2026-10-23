import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:rxdart/rxdart.dart';

/// Whether sound is coming from the phone's own speaker, with no headphones,
/// Bluetooth, USB or other output connected. The in-app equalizer is skipped
/// then: boosting a phone speaker only makes it distort.
class OutputRoute {
  OutputRoute._();

  static final phoneSpeaker = BehaviorSubject<bool>.seeded(false);
  static StreamSubscription? _sub;

  /// Device types that are part of the phone itself, not a listening device.
  static const _phoneOwn = {
    AudioDeviceType.unknown,
    AudioDeviceType.builtInEarpiece,
    AudioDeviceType.builtInSpeaker,
    AudioDeviceType.builtInSpeakerSafe,
    AudioDeviceType.builtInMic,
    AudioDeviceType.telephony,
    AudioDeviceType.fm,
    AudioDeviceType.fmTuner,
    AudioDeviceType.tvTuner,
    AudioDeviceType.ip,
    AudioDeviceType.bus,
    AudioDeviceType.virtual,
  };

  /// True when none of [outputs] is a headphone, Bluetooth, USB or similar
  /// device.
  static bool isPhoneSpeakerOnly(Iterable<AudioDeviceType> outputs) =>
      outputs.every(_phoneOwn.contains);

  /// Starts watching the outputs. Phones only: desktops report no devices
  /// here and have no built-in speaker to protect.
  static Future<void> start(AudioSession session) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    Future<void> refresh() async {
      try {
        final devices = await session.getDevices(includeInputs: false);
        phoneSpeaker.add(isPhoneSpeakerOnly(devices.map((d) => d.type)));
      } catch (_) {
        // Keep the last known state.
      }
    }

    await refresh();
    _sub ??= session.devicesChangedEventStream.listen((_) => refresh());
  }
}
