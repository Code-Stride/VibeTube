import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Owns the OS audio session: routing, focus, and — importantly — reacting to
/// the events every other media app reacts to.
///
/// Configuring the session alone is not enough. Without listening for
/// interruptions, unplugging headphones keeps blasting audio out of the phone
/// speaker, and an incoming call talks over the video. Both are handled here
/// and fanned out to whichever component currently owns the player.
class AudioHelper {
  static bool _ready = false;
  static bool _wired = false;

  // Multiple owners (full player, mini player) may be alive across a
  // transition, so listeners are kept in lists rather than single slots —
  // the same pattern NativePlayer uses for media-button handlers.
  static final List<void Function()> _noisyListeners = [];
  static final List<void Function(bool permanent)> _pauseListeners = [];
  static final List<void Function()> _resumeListeners = [];
  static final List<void Function(bool ducking)> _duckListeners = [];

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
        // We duck ourselves (see _duckListeners) so a notification lowers the
        // volume briefly instead of pausing the video outright.
        androidWillPauseWhenDucked: false,
      ));
      _ready = true;
      await _wireEvents(session);
    } catch (e) {
      debugPrint('AudioHelper.configure: $e');
    }
  }

  static Future<void> _wireEvents(AudioSession session) async {
    if (_wired) return;
    _wired = true;

    // Headphones unplugged / Bluetooth disconnected. Android delivers
    // ACTION_AUDIO_BECOMING_NOISY; not pausing here is what makes a phone
    // suddenly play out loud in public.
    session.becomingNoisyEventStream.listen((_) {
      for (final l in List.of(_noisyListeners)) {
        l();
      }
    });

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Short notification: drop the volume, keep playing.
            for (final l in List.of(_duckListeners)) {
              l(true);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // Phone call or another media app took focus.
            // `pause` is recoverable, `unknown` is not.
            final permanent = event.type == AudioInterruptionType.unknown;
            for (final l in List.of(_pauseListeners)) {
              l(permanent);
            }
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            for (final l in List.of(_duckListeners)) {
              l(false);
            }
            break;
          case AudioInterruptionType.pause:
            for (final l in List.of(_resumeListeners)) {
              l();
            }
            break;
          case AudioInterruptionType.unknown:
            // Focus was lost for good; staying paused is correct.
            break;
        }
      }
    });
  }

  /// Register interruption handlers. Safe to call repeatedly.
  static void addListeners({
    void Function()? onBecomingNoisy,
    void Function(bool permanent)? onShouldPause,
    void Function()? onMayResume,
    void Function(bool ducking)? onDuck,
  }) {
    if (onBecomingNoisy != null && !_noisyListeners.contains(onBecomingNoisy)) {
      _noisyListeners.add(onBecomingNoisy);
    }
    if (onShouldPause != null && !_pauseListeners.contains(onShouldPause)) {
      _pauseListeners.add(onShouldPause);
    }
    if (onMayResume != null && !_resumeListeners.contains(onMayResume)) {
      _resumeListeners.add(onMayResume);
    }
    if (onDuck != null && !_duckListeners.contains(onDuck)) {
      _duckListeners.add(onDuck);
    }
  }

  static void removeListeners({
    void Function()? onBecomingNoisy,
    void Function(bool permanent)? onShouldPause,
    void Function()? onMayResume,
    void Function(bool ducking)? onDuck,
  }) {
    if (onBecomingNoisy != null) _noisyListeners.remove(onBecomingNoisy);
    if (onShouldPause != null) _pauseListeners.remove(onShouldPause);
    if (onMayResume != null) _resumeListeners.remove(onMayResume);
    if (onDuck != null) _duckListeners.remove(onDuck);
  }

  /// Volume applied while ducking. Matches what most players use — quiet
  /// enough to hear a notification over, loud enough not to feel muted.
  static const double duckVolume = 0.3;

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
