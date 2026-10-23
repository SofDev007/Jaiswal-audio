// Saved equalizer profiles, profile names, and the phone-speaker rule.

import 'package:Bloomee/services/player/eq_profiles.dart';
import 'package:Bloomee/services/player/output_route.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiles survive a save and load', () {
    final raw = encodeEqProfiles([
      (name: 'Car', gains: [3.5, 2, 0, 0, 0, 0, 0, 1, 2, 3]),
    ]);
    final back = decodeEqProfiles(raw).single;
    expect(back.name, 'Car');
    expect(back.gains, [3.5, 2, 0, 0, 0, 0, 0, 1, 2, 3]);
    expect(decodeEqProfiles(null), isEmpty);
    expect(decodeEqProfiles('not json'), isEmpty);
  });

  test('profile names must be new and not blank', () {
    expect(eqProfileNameError('  ', []), isNotNull);
    expect(eqProfileNameError('Rock', ['Flat', 'Rock']), isNotNull);
    expect(eqProfileNameError('rock', ['Rock']), isNotNull);
    expect(eqProfileNameError('Custom', []), isNotNull);
    expect(eqProfileNameError('x' * 31, []), isNotNull);
    expect(eqProfileNameError('My EQ', ['Flat']), isNull);
  });

  test('EQ is skipped only when nothing but the phone plays sound', () {
    expect(
        OutputRoute.isPhoneSpeakerOnly([
          AudioDeviceType.builtInSpeaker,
          AudioDeviceType.builtInEarpiece,
          AudioDeviceType.telephony,
        ]),
        isTrue);
    expect(
        OutputRoute.isPhoneSpeakerOnly(
            [AudioDeviceType.builtInSpeaker, AudioDeviceType.wiredHeadphones]),
        isFalse);
    expect(
        OutputRoute.isPhoneSpeakerOnly(
            [AudioDeviceType.builtInSpeaker, AudioDeviceType.bluetoothA2dp]),
        isFalse);
    expect(
        OutputRoute.isPhoneSpeakerOnly(
            [AudioDeviceType.builtInSpeaker, AudioDeviceType.usbAudio]),
        isFalse);
  });
}
