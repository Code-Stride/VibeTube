import 'package:flutter/services.dart';

/// Bridges to Android MainActivity for PiP + MediaSession background service.
///
/// Handlers are multiplexed so PlayerScreen and MiniPlayerController can both
/// listen without overwriting each other (last-writer-wins bug).
class NativePlayer {
  static const _ch = MethodChannel('com.blazenxt.vibetube/player');
  static bool _wired = false;

  static final List<void Function(bool)> _pipListeners = [];
  static final List<void Function()> _playListeners = [];
  static final List<void Function()> _pauseListeners = [];
  static final List<void Function()> _stopListeners = [];
  static final List<void Function()> _rewindListeners = [];
  static final List<void Function()> _forwardListeners = [];
  static final List<void Function(Duration)> _seekListeners = [];

  static void _ensureChannelWired() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipChanged':
          final v = call.arguments == true;
          for (final l in List.of(_pipListeners)) {
            l(v);
          }
          break;
        case 'mediaPlay':
          for (final l in List.of(_playListeners)) {
            l();
          }
          break;
        case 'mediaPause':
          for (final l in List.of(_pauseListeners)) {
            l();
          }
          break;
        case 'mediaStop':
          for (final l in List.of(_stopListeners)) {
            l();
          }
          break;
        // Sent by the PiP window's rewind / forward buttons.
        case 'mediaRewind':
          for (final l in List.of(_rewindListeners)) {
            l();
          }
          break;
        case 'mediaForward':
          for (final l in List.of(_forwardListeners)) {
            l();
          }
          break;
        // Lock-screen / Android Auto scrubber.
        case 'mediaSeekTo':
          final ms = call.arguments;
          if (ms is int) {
            for (final l in List.of(_seekListeners)) {
              l(Duration(milliseconds: ms));
            }
          }
          break;
      }
    });
  }

  /// Register listeners (safe to call multiple times from different owners).
  static void ensureHandlers({
    void Function(bool inPip)? onPip,
    void Function()? onMediaPlay,
    void Function()? onMediaPause,
    void Function()? onMediaStop,
    void Function()? onMediaRewind,
    void Function()? onMediaForward,
    void Function(Duration)? onMediaSeek,
  }) {
    _ensureChannelWired();
    if (onMediaSeek != null && !_seekListeners.contains(onMediaSeek)) {
      _seekListeners.add(onMediaSeek);
    }
    if (onPip != null && !_pipListeners.contains(onPip)) {
      _pipListeners.add(onPip);
    }
    if (onMediaPlay != null && !_playListeners.contains(onMediaPlay)) {
      _playListeners.add(onMediaPlay);
    }
    if (onMediaPause != null && !_pauseListeners.contains(onMediaPause)) {
      _pauseListeners.add(onMediaPause);
    }
    if (onMediaStop != null && !_stopListeners.contains(onMediaStop)) {
      _stopListeners.add(onMediaStop);
    }
    if (onMediaRewind != null && !_rewindListeners.contains(onMediaRewind)) {
      _rewindListeners.add(onMediaRewind);
    }
    if (onMediaForward != null && !_forwardListeners.contains(onMediaForward)) {
      _forwardListeners.add(onMediaForward);
    }
  }

  static void removeHandlers({
    void Function(bool inPip)? onPip,
    void Function()? onMediaPlay,
    void Function()? onMediaPause,
    void Function()? onMediaStop,
    void Function()? onMediaRewind,
    void Function()? onMediaForward,
    void Function(Duration)? onMediaSeek,
  }) {
    if (onMediaSeek != null) _seekListeners.remove(onMediaSeek);
    if (onPip != null) _pipListeners.remove(onPip);
    if (onMediaPlay != null) _playListeners.remove(onMediaPlay);
    if (onMediaPause != null) _pauseListeners.remove(onMediaPause);
    if (onMediaStop != null) _stopListeners.remove(onMediaStop);
    if (onMediaRewind != null) _rewindListeners.remove(onMediaRewind);
    if (onMediaForward != null) _forwardListeners.remove(onMediaForward);
  }

  static Future<bool> isPipSupported() async {
    try {
      return await _ch.invokeMethod<bool>('isPipSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enterPip() async {
    try {
      return await _ch.invokeMethod<bool>('enterPip') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoPip(bool enabled) async {
    try {
      await _ch.invokeMethod('setAutoPip', {'enabled': enabled});
    } catch (_) {}
  }

  /// Tell native the real video dimensions so the PiP window matches the
  /// content instead of assuming 16:9 (Shorts are 9:16).
  static Future<void> setVideoAspect(int width, int height) async {
    if (width <= 0 || height <= 0) return;
    try {
      await _ch.invokeMethod('setVideoAspect', {
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }

  /// [position] / [duration] feed the MediaSession playback state so the
  /// lock-screen, Bluetooth and Android Auto scrubbers show real progress.
  static Future<void> setPlaying(
    bool playing, {
    Duration? position,
    Duration? duration,
    double? speed,
  }) async {
    try {
      await _ch.invokeMethod('setPlaying', {
        'playing': playing,
        if (position != null) 'positionMs': position.inMilliseconds,
        if (duration != null) 'durationMs': duration.inMilliseconds,
        if (speed != null) 'speed': speed,
      });
    } catch (_) {}
  }

  static Future<void> startBackground({
    required String title,
    required String artist,
    bool playing = true,
  }) async {
    try {
      await _ch.invokeMethod('startBackground', {
        'title': title,
        'artist': artist,
        'playing': playing,
      });
    } catch (_) {}
  }

  static Future<void> updateBackground({
    required String title,
    required String artist,
    required bool playing,
    Duration? position,
    Duration? duration,
  }) async {
    try {
      await _ch.invokeMethod('updateBackground', {
        'title': title,
        'artist': artist,
        'playing': playing,
        if (position != null) 'positionMs': position.inMilliseconds,
        if (duration != null) 'durationMs': duration.inMilliseconds,
      });
    } catch (_) {}
  }

  static Future<void> stopBackground() async {
    try {
      await _ch.invokeMethod('stopBackground');
    } catch (_) {}
  }
}
