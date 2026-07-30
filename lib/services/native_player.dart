import 'package:flutter/services.dart';

/// Bridges to Android MainActivity for PiP + MediaSession background service.
class NativePlayer {
  static const _ch = MethodChannel('com.blazenxt.vibetube/player');
  static bool _handlerSet = false;

  static void ensureHandlers({
    void Function(bool inPip)? onPip,
    void Function()? onMediaPlay,
    void Function()? onMediaPause,
    void Function()? onMediaStop,
  }) {
    if (_handlerSet &&
        onPip == null &&
        onMediaPlay == null &&
        onMediaPause == null &&
        onMediaStop == null) {
      return;
    }
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipChanged':
          onPip?.call(call.arguments == true);
          break;
        case 'mediaPlay':
          onMediaPlay?.call();
          break;
        case 'mediaPause':
          onMediaPause?.call();
          break;
        case 'mediaStop':
          onMediaStop?.call();
          break;
      }
    });
  }

  static Future<bool> isPipSupported() async {
    try {
      return await _ch.invokeMethod<bool>('isPipSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enters PiP only if native side also believes playback is active.
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

  /// Tell native whether media is currently playing (gates auto-PiP).
  static Future<void> setPlaying(bool playing) async {
    try {
      await _ch.invokeMethod('setPlaying', {'playing': playing});
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
  }) async {
    try {
      await _ch.invokeMethod('updateBackground', {
        'title': title,
        'artist': artist,
        'playing': playing,
      });
    } catch (_) {}
  }

  static Future<void> stopBackground() async {
    try {
      await _ch.invokeMethod('stopBackground');
    } catch (_) {}
  }

  @Deprecated('Use ensureHandlers')
  static void listenPip(void Function(bool inPip) onChanged) {
    ensureHandlers(onPip: onChanged);
  }
}
