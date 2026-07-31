import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../models/video.dart';
import '../services/native_player.dart';
import '../services/audio_helper.dart';

/// App-wide playback session — survives leaving the full player (YouTube-style mini player).
class MiniPlayerController extends ChangeNotifier {
  VideoPlayerController? controller;
  Video? video;
  VideoDetails? details;
  String? activeUrl;
  String quality = 'Auto (HLS)';
  double speed = 1.0;

  // Throttle _tick notifications to avoid rebuilding widget tree every frame (~60fps)
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _notifyIntervalMs = 250;

  bool get hasSession => controller != null && video != null;
  bool get isReady =>
      controller != null && controller!.value.isInitialized;
  bool get isPlaying => isReady && controller!.value.isPlaying;

  bool _minimized = false;
  bool get minimized => _minimized && hasSession;

  /// Full player is on screen — hide mini bar.
  bool _expanded = false;
  bool get expanded => _expanded;

  bool get showMiniBar => hasSession && minimized && !_expanded;

  /// When false, HomeScreen renders the bar above bottom navigation.
  bool useGlobalOverlay = false;

  void setExpanded(bool v) {
    if (_expanded == v) return;
    _expanded = v;
    if (v) {
      _minimized = false;
      // Full player owns ticks while expanded
      controller?.removeListener(_tick);
    } else if (controller != null) {
      controller!.removeListener(_tick);
      controller!.addListener(_tick);
    }
    notifyListeners();
  }

  void setUseGlobalOverlay(bool v) {
    if (useGlobalOverlay == v) return;
    useGlobalOverlay = v;
    notifyListeners();
  }

  /// Hand controller from full player to mini session (back pressed).
  void adopt({
    required VideoPlayerController ctrl,
    required Video video,
    VideoDetails? details,
    String? activeUrl,
    String quality = 'Auto (HLS)',
    double speed = 1.0,
  }) {
    // Don't dispose the incoming controller — it becomes ours.
    if (controller != null && !identical(controller, ctrl)) {
      try {
        controller!.removeListener(_tick);
        controller!.dispose();
      } catch (_) {}
    }
    controller = ctrl;
    this.video = video;
    this.details = details;
    this.activeUrl = activeUrl;
    this.quality = quality;
    this.speed = speed;
    _minimized = true;
    _expanded = false;
    controller!.removeListener(_tick);
    controller!.addListener(_tick);
    NativePlayer.ensureHandlers(
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );
    _syncBackground();
    notifyListeners();
  }

  void _tick() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < _notifyIntervalMs) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _onMediaPlay() {
    play();
  }

  void _onMediaPause() {
    pause();
  }

  void _onMediaStop() {
    close();
  }

  Future<void> togglePlay() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await AudioHelper.requestFocus();
      await c.play();
    }
    _syncBackground();
    notifyListeners();
  }

  Future<void> play() async {
    await AudioHelper.requestFocus();
    await controller?.play();
    _syncBackground();
    notifyListeners();
  }

  Future<void> pause() async {
    await controller?.pause();
    await NativePlayer.stopBackground();
    notifyListeners();
  }

  void _syncBackground() {
    final c = controller;
    final v = video;
    if (c == null || !c.value.isInitialized || v == null) return;
    final playing = c.value.isPlaying;
    NativePlayer.setPlaying(playing);
    NativePlayer.startBackground(
      title: v.title,
      artist: v.channelName.isEmpty ? 'VibeTube' : v.channelName,
      playing: playing,
    );
  }

  /// Close mini player completely and free decoder.
  Future<void> close() async {
    NativePlayer.removeHandlers(
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );
    final c = controller;
    controller = null;
    video = null;
    details = null;
    activeUrl = null;
    _minimized = false;
    _expanded = false;
    if (c != null) {
      try {
        c.removeListener(_tick);
        await c.pause();
        await c.dispose();
      } catch (_) {}
    }
    await NativePlayer.setPlaying(false);
    await NativePlayer.stopBackground();
    notifyListeners();
  }

  /// Take controller back into full player (clears mini ownership without dispose).
  VideoPlayerController? takeForExpansion() {
    final c = controller;
    if (c != null) {
      c.removeListener(_tick);
    }
    // Keep references; full player will re-adopt listeners
    _expanded = true;
    _minimized = false;
    notifyListeners();
    return c;
  }

  /// After full player rebuilds with same session, re-bind.
  void bindExisting(VideoPlayerController ctrl) {
    if (!identical(controller, ctrl)) {
      controller?.removeListener(_tick);
      controller = ctrl;
    }
    // Expanded: do not double-listen; PlayerScreen drives UI
    controller?.removeListener(_tick);
    _expanded = true;
    _minimized = false;
    notifyListeners();
  }

  void updateMeta({Video? video, VideoDetails? details, String? activeUrl}) {
    if (video != null) this.video = video;
    if (details != null) this.details = details;
    if (activeUrl != null) this.activeUrl = activeUrl;
    notifyListeners();
  }

  @override
  void dispose() {
    final c = controller;
    controller = null;
    if (c != null) {
      try {
        c.removeListener(_tick);
        c.dispose();
      } catch (_) {}
    }
    // Stop background media notification so it doesn't persist as a zombie
    NativePlayer.setPlaying(false);
    NativePlayer.stopBackground();
    super.dispose();
  }
}
