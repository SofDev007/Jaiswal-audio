import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:rxdart/rxdart.dart';

/// Whether sound is coming from the phone's own speaker, with no headphones
/// (jack or USB-C) or Bluetooth device connected. The in-app equalizer only
/// runs on those: boosting a phone speaker only makes it distort.
class OutputRoute {
  OutputRoute._();

  /// Phones start as "speaker" so the EQ never plays on it before the first
  /// device check; desktops have no speaker to protect.
  static final phoneSpeaker =
      BehaviorSubject<bool>.seeded(Platform.isAndroid || Platform.isIOS);
  static StreamSubscription? _sub;

  /// Headphones and Bluetooth: the only outputs the EQ is allowed on.
  static const _listening = {
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.wiredHeadphones,
    AudioDeviceType.usbAudio, // USB-C earphones / dongles on jack-less phones
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothSco,
    AudioDeviceType.bluetoothLe,
    AudioDeviceType.hearingAid,
  };

  /// True when none of [outputs] is headphones or a Bluetooth device.
  static bool isPhoneSpeakerOnly(Iterable<AudioDeviceType> outputs) =>
      !outputs.any(_listening.contains);

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
