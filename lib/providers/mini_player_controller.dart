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
      // Collapsing while a session is alive: fall back to the mini bar,
      // otherwise playback would continue with no visible control surface.
      _minimized = true;
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
    // New session: the media notification must be (re)started, not updated.
    _bgStarted = false;
    controller!.removeListener(_tick);
    controller!.addListener(_tick);
    NativePlayer.ensureHandlers(
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );
    AudioHelper.addListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
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
      _pausedByInterruption = false;
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
    // Keep the MediaSession alive on pause so lock-screen / notification
    // controls remain usable to resume. Only close() tears it down.
    await NativePlayer.setPlaying(false);
    _syncBackground();
    notifyListeners();
  }

  /// True once the foreground MediaSession service has been started for this
  /// session, so later syncs update it instead of re-starting it.
  bool _bgStarted = false;

  /// Paused by the OS rather than the user, so auto-resume is appropriate.
  bool _pausedByInterruption = false;

  void _onBecomingNoisy() {
    final c = controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    _pausedByInterruption = false;
    pause();
  }

  void _onShouldPause(bool permanent) {
    final c = controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    _pausedByInterruption = !permanent;
    pause();
  }

  void _onMayResume() {
    if (!_pausedByInterruption) return;
    _pausedByInterruption = false;
    final c = controller;
    if (c == null || !c.value.isInitialized || c.value.isPlaying) return;
    play();
  }

  void _onDuck(bool ducking) {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    c.setVolume(ducking ? AudioHelper.duckVolume : 1.0);
  }

  void _syncBackground() {
    final c = controller;
    final v = video;
    if (c == null || !c.value.isInitialized || v == null) return;
    final playing = c.value.isPlaying;
    final artist = v.channelName.isEmpty ? 'VibeTube' : v.channelName;
    NativePlayer.setPlaying(playing);
    if (_bgStarted) {
      NativePlayer.updateBackground(
        title: v.title,
        artist: artist,
        playing: playing,
      );
    } else {
      NativePlayer.startBackground(
        title: v.title,
        artist: artist,
        playing: playing,
      );
      _bgStarted = true;
    }
  }

  /// Close mini player completely and free decoder.
  Future<void> close() async {
    NativePlayer.removeHandlers(
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );
    AudioHelper.removeListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
    );
    final c = controller;
    controller = null;
    video = null;
    details = null;
    activeUrl = null;
    _minimized = false;
    _expanded = false;
    _bgStarted = false;
    _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
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

  /// Give up ownership of the current controller *without* disposing it.
  /// Used when the full player replaces the borrowed controller (e.g. the user
  /// switched quality) and becomes responsible for disposing the old one.
  void detachController() {
    final c = controller;
    if (c == null) return;
    c.removeListener(_tick);
    controller = null;
    notifyListeners();
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
