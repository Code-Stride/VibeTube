import 'package:flutter/services.dart';

/// Bridges to Android MainActivity for PiP + background foreground service.
class NativePlayer {
  static const _ch = MethodChannel('com.blazenxt.vibetube/player');

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

  static Future<void> startBackground({
    required String title,
    required String artist,
  }) async {
    try {
      await _ch.invokeMethod('startBackground', {
        'title': title,
        'artist': artist,
      });
    } catch (_) {}
  }

  static Future<void> stopBackground() async {
    try {
      await _ch.invokeMethod('stopBackground');
    } catch (_) {}
  }

  static void listenPip(void Function(bool inPip) onChanged) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        onChanged(call.arguments == true);
      }
    });
  }
}
