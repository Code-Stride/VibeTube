import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Configures OS audio session so playback continues when screen is off
/// and appears on system media output / BT.
class AudioHelper {
  static bool _ready = false;

  static Future<void> configure() async {
    if (_ready) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
          flags: AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _ready = true;
    } catch (e) {
      debugPrint('AudioHelper.configure: $e');
    }
  }

  static Future<bool> requestFocus() async {
    try {
      final session = await AudioSession.instance;
      return await session.setActive(true);
    } catch (e) {
      debugPrint('AudioHelper.requestFocus: $e');
      return false;
    }
  }

  static Future<void> abandonFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }
}
