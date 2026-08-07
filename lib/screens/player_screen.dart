import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/video.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../utils/text_utils.dart';
import '../utils/share_links.dart';
import '../widgets/video_card.dart';
import '../widgets/caption_overlay.dart';
import '../services/native_player.dart';
import '../services/audio_helper.dart';
import '../providers/mini_player_controller.dart';
import '../services/permissions.dart';

class PlayerScreen extends StatefulWidget {
  final String videoId;
  final Video? preview;
  final String? localPath;
  final bool resumeSession;

  const PlayerScreen({
    super.key,
    required this.videoId,
    this.preview,
    this.localPath,
    this.resumeSession = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  /// False while the app is backgrounded, so periodic UI work can pause.
  bool _appResumed = true;

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _showControls = true;
  bool _isBuffering = true;
  bool _liked = false;
  bool _fullscreen = false;
  double _speed = 1.0;
  String _quality = 'Auto';
  String? _activeUrl;
  bool _sponsorToast = false;
  String _sponsorLabel = '';
  Timer? _hideTimer;
  Timer? _posTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeking = false;
  double _seekValue = 0;
  int? _dislikes;
  bool _descExpanded = false;
  bool _inPip = false;
  bool _bgActive = false;
  bool _pipSupported = false;
  bool _handedToMini = false;

  /// True when this screen borrowed the mini player's controller instead of
  /// creating its own — it must not dispose it.
  bool _borrowedFromMini = false;
  bool _lastNativePlaying = false;
  bool _looping = false;
  bool _muted = false;
  int _attachRequestId = 0;
  int _playbackRequestId = 0;

  /// True when playback was paused by the OS (call, other app) rather than by
  /// the user, so we know whether resuming automatically is appropriate.
  bool _pausedByInterruption = false;

  /// Pre-duck volume, restored when the interruption ends.
  double _preDuckVolume = 1.0;
  bool _watchLater = false;
  bool _subscribed = false;
  String? _toastMsg;
  Timer? _toastTimer;
  Timer? _sponsorToastTimer;

  /// When true, audio session interruption callbacks are suppressed because
  /// WE initiated the focus change (play/pause). Without this guard,
  /// requesting audio focus triggers _onShouldPause which immediately pauses.
  bool _requestingFocus = false;
  int _focusGuardToken = 0;
  DateTime _lastPlayTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _onMediaPlay() async {
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      await c.play();
      if (mounted) setState(() {});
      await _syncNativePlayback(forceBg: true);
    }
  }

  void _onMediaPause() async {
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      await c.pause();
      if (mounted) setState(() {});
      await _syncNativePlayback(forceBg: true);
    }
  }

  void _onMediaStop() async {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      await c.pause();
    }
    await NativePlayer.setPlaying(false);
    await NativePlayer.stopBackground();
    _bgActive = false;
    if (mounted) setState(() {});
  }

  /// Headphones pulled out / Bluetooth dropped: pause, like every other
  /// media app, instead of switching to the loudspeaker.
  void _onBecomingNoisy() {
    if (_requestingFocus) return;
    if (DateTime.now().difference(_lastPlayTime).inMilliseconds < 1000) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    c.pause();
    _pausedByInterruption = false; // user-visible pause; don't auto-resume
    if (mounted) setState(() {});
    _syncNativePlayback(forceBg: true);
  }

  /// Call or another media app took audio focus.
  void _onShouldPause(bool permanent) {
    if (_requestingFocus) return;
    if (DateTime.now().difference(_lastPlayTime).inMilliseconds < 1000) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    c.pause();
    _pausedByInterruption = !permanent;
    if (mounted) setState(() {});
    _syncNativePlayback(forceBg: true);
  }

  /// Focus handed back. Only resume if *we* were the ones interrupted.
  void _onMayResume() {
    if (!_pausedByInterruption || _requestingFocus) return;
    _pausedByInterruption = false;
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isPlaying) return;
    _requestingFocus = true;
    // Guard released from a finally, and the controller re-checked after the
    // await: the old .then() had no catchError, so a throw from requestFocus()
    // (or a controller disposed meanwhile) left _requestingFocus stuck on —
    // and every interruption handler early-returns while it is set, silently
    // disabling call / headset / duck handling for the rest of the session.
    () async {
      try {
        await AudioHelper.requestFocus();
        if (!mounted || _controller != c) return;
        await c.play();
      } catch (e) {
        debugPrint('resume after interruption failed: $e');
      } finally {
        _releaseFocusGuardSoon();
      }
      if (!mounted) return;
      setState(() {});
      _syncNativePlayback(forceBg: true);
    }();
  }

  /// Transient sound (notification): duck rather than pause.
  void _onDuck(bool ducking) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (ducking) {
      _preDuckVolume = _muted ? 0 : 1;
      c.setVolume(_muted ? 0 : AudioHelper.duckVolume);
    } else {
      c.setVolume(_muted ? 0 : _preDuckVolume);
    }
  }

  /// PiP window rewind / forward buttons.
  void _onMediaRewind() => _seekBy(-10);
  void _onMediaForward() => _seekBy(10);

  void _onPipChanged(bool inPip) {
    if (!mounted) return;
    setState(() {
      _inPip = inPip;
      // Entering PiP: drop the overlay so it can't reappear on exit.
      if (inPip) _showControls = false;
    });
    if (inPip) {
      _hideTimer?.cancel();
    } else {
      _armHide();
    }
    _applyWakelock(playing: _controller?.value.isPlaying == true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Registered synchronously, before any await. _boot() used to do this
    // after several awaits, so a screen popped during that window had
    // dispose() remove handlers that had not been added yet — and _boot then
    // added them to a dead State, leaking a listener that fired forever.
    NativePlayer.ensureHandlers(
      onPip: _onPipChanged,
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
      onMediaRewind: _onMediaRewind,
      onMediaForward: _onMediaForward,
    );
    AudioHelper.addListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
    );
    _boot();
  }

  Future<void> _boot() async {
    final provider = context.read<AppProvider>();
    final mini = context.read<MiniPlayerController>();
    // Deferred: this runs inside initState, and notifyListeners() there would
    // mark the global mini-player Consumer dirty during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) mini.setExpanded(true);
    });

    _speed = provider.defaultSpeed;
    // Fall back to adaptive, not a hard 1080p lock that many videos cannot
    // serve (see the defaultQuality mismatch in AppProvider).
    _quality = provider.defaultQuality.isEmpty
        ? 'Auto (HLS)'
        : provider.defaultQuality;
    if (_quality == 'Auto') _quality = 'Auto (HLS)';
    _liked = await provider.isLiked(widget.videoId);
    try {
      _watchLater = provider.watchLater.any((e) => e.id == widget.videoId);
    } catch (_) {}
    _pipSupported = await NativePlayer.isPipSupported();
    if (!mounted) return;
    await NativePlayer.setAutoPip(provider.isAutoPipEnabled);
    await NativePlayer.setPlaying(false);
    if (!mounted) return;
    // Ask for the notification permission here rather than at app start:
    // this is the first moment a media notification is actually needed.
    if (provider.isBackgroundPlayEnabled) {
      unawaited(ensureNotificationPermission());
    }

    // Resume from mini player — same controller, no reload
    if (widget.resumeSession &&
        mini.hasSession &&
        mini.video?.id == widget.videoId &&
        mini.controller != null &&
        mini.controller!.value.isInitialized) {
      _borrowedFromMini = true;
      final resumed = mini.controller!;
      _controller = resumed;
      _activeUrl = mini.activeUrl;
      _quality = mini.quality;
      _speed = mini.speed;
      _ready = true;
      _isBuffering = false;
      _duration = resumed.value.duration;
      _position = resumed.value.position;
      resumed.removeListener(_onTick);
      resumed.addListener(_onTick);
      mini.bindExisting(resumed);
      _startPosTimer();
      _armHide();
      if (mounted) setState(() {});
      // refresh side data quietly
      if (provider.currentVideo?.id != widget.videoId) {
        provider.loadVideoDetails(widget.videoId, preview: widget.preview);
      }
      _dislikes = provider.dislikeCount;
      return;
    }

    // Opening a different video while mini is open — close mini first
    if (mini.hasSession && mini.video?.id != widget.videoId) {
      await mini.close();
    }

    // Offline local file
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      try {
        await _attachController(widget.localPath!);
        provider.loadVideoDetails(widget.videoId, preview: widget.preview);
        return;
      } catch (e) {
        _log('local play failed: $e');
      }
    }

    await provider.loadVideoDetails(widget.videoId, preview: widget.preview);
    if (!mounted) return;

    final details = provider.currentVideo;
    if (details == null) {
      setState(() => _isBuffering = false);
      return;
    }
    _dislikes = provider.dislikeCount;
    await _startPlayback(details);
  }

  Future<void> _startPlayback(
    VideoDetails details, {
    String? quality,
    Duration? resumeAt,
  }) async {
    final playbackRequestId = ++_playbackRequestId;
    final q = (details.isLive) ? 'Auto (HLS)' : (quality ?? _quality);
    // Live streams require HLS / DASH — force Auto HLS path

    final candidates = <String>[];
    void add(String? u) {
      if (u != null && u.isNotEmpty && !candidates.contains(u)) {
        candidates.add(u);
      }
    }

    final isAuto =
        details.isLive ||
        q.startsWith('Auto') ||
        q == 'Best' ||
        q == 'Auto (HLS)';
    final target = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (details.isLive) {
      // LIVE: HLS/DASH only (ANDROID HLS verified). No progressive.
      add(details.hlsUrl);
      add(details.dashUrl);
      if (details.hlsVariants.isNotEmpty) {
        final hs = details.hlsVariants.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final h in hs) {
          add(details.hlsVariants[h]);
        }
      }
      add(details.preferredPlayUrl);
    } else if (isAuto) {
      // Try highest quality HLS variants FIRST (not master playlist)
      if (details.hlsVariants.isNotEmpty) {
        final hs = details.hlsVariants.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final prefer in [2160, 1440, 1080, 720, 480]) {
          if (details.hlsVariants.containsKey(prefer)) {
            add(details.hlsVariants[prefer]);
          }
        }
        for (final h in hs) {
          add(details.hlsVariants[h]);
        }
      }
      add(details.hlsUrl);
      add(details.preferredPlayUrl);
      add(details.bestMuxedUrl);
    } else if (q == 'Audio Only') {
      add(details.urlForQuality(q));
      add(details.bestMuxedUrl);
    } else {
      // Locked quality. The old code appended every other height and then the
      // adaptive master playlist, so a failure at the requested height
      // silently landed on 360p — the lock did nothing. Only offer streams at
      // (or very near) the requested height, and never the adaptive master,
      // which would re-introduce automatic switching.
      const tolerance = 20; // 1080 vs 1088 etc.
      bool near(int h) => (h - target).abs() <= tolerance;

      if (target > 0) {
        // Exact HLS variant is the best lock available.
        if (details.hlsVariants.containsKey(target)) {
          add(details.hlsVariants[target]);
        }
        for (final h in details.hlsVariants.keys.where(near)) {
          add(details.hlsVariants[h]);
        }
        // Progressive muxed at the same height.
        if (details.progressiveByHeight.containsKey(target)) {
          add(details.progressiveByHeight[target]);
        }
        for (final h in details.progressiveByHeight.keys.where(near)) {
          add(details.progressiveByHeight[h]);
        }
        // Muxed formats list, same height only.
        for (final f in details.formats.where(
          (f) => f.isMuxed && f.url.isNotEmpty && near(f.height),
        )) {
          add(f.url);
        }
      } else {
        add(details.urlForQuality(q));
      }
    }

    if (candidates.isEmpty) {
      if (!mounted) return;
      final lockFailed = !isAuto && q != 'Audio Only' && target > 0;
      setState(() {
        _isBuffering = false;
        _ready = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lockFailed
                ? '$q is not available for this video'
                : 'No playable stream for this video',
          ),
          action: lockFailed
              ? SnackBarAction(
                  label: 'Use Auto',
                  onPressed: () {
                    setState(() => _quality = 'Auto (HLS)');
                    _startPlayback(details, quality: 'Auto (HLS)');
                  },
                )
              : null,
        ),
      );
      return;
    }

    _log(
      'Quality=$q candidates=${candidates.length} hlsVars=${details.hlsVariants.keys.toList()} prog=${details.progressiveByHeight.keys.toList()} hlsMaster=${details.hlsUrl != null}',
    );

    Object? lastErr;
    for (final url in candidates) {
      if (playbackRequestId != _playbackRequestId) return;
      try {
        final attached = await _attachController(url, resumeAt: resumeAt);
        if (attached) {
          final tag = url.contains('m3u8')
              ? (url == details.hlsUrl ? 'HLS-master' : 'HLS-variant')
              : 'MP4';
          _log('Playing $q via $tag');
          if (mounted) setState(() {}); // refresh quality label if needed
          return;
        }
      } catch (e) {
        if (playbackRequestId != _playbackRequestId) return;
        lastErr = e;
        _log('candidate failed: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isBuffering = false;
        _ready = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback failed ($q): $lastErr')));
    }
  }

  /// Returns true only when this call actually attached a live controller.
  ///
  /// Callers used to read the `_ready` *field* afterwards, which could still
  /// hold `true` from a previous attach when `_finishAttach` bailed out on a
  /// request-ID mismatch — so a failed quality switch reported success and
  /// left the old stream playing.
  Future<bool> _attachController(String url, {Duration? resumeAt}) async {
    final requestId = ++_attachRequestId;
    if (mounted) setState(() => _isBuffering = true);

    final isLocal = url.startsWith('/') || url.startsWith('file:');
    final isHls = url.contains('m3u8') || url.contains('/manifest/hls');
    if (isLocal) {
      final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
      final candidate = VideoPlayerController.file(File(path));
      try {
        await candidate.initialize().timeout(const Duration(seconds: 20));
        return await _finishAttach(
          candidate,
          url,
          resumeAt: resumeAt,
          requestId: requestId,
        );
      } catch (_) {
        await candidate.dispose();
        if (requestId == _attachRequestId && mounted) {
          setState(() => _isBuffering = false);
        }
        rethrow;
      }
    }

    final headerSets = <Map<String, String>?>[
      if (isHls)
        {
          'User-Agent':
              'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          'Accept': '*/*',
        }
      else
        {
          'User-Agent':
              'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
          'Referer': 'https://www.youtube.com/',
          'Origin': 'https://www.youtube.com',
        },
      null,
      {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      },
    ];

    Object? lastErr;
    for (final headers in headerSets) {
      if (requestId != _attachRequestId) return false;
      VideoPlayerController? candidate;
      try {
        candidate = headers == null
            ? VideoPlayerController.networkUrl(Uri.parse(url))
            : VideoPlayerController.networkUrl(
                Uri.parse(url),
                httpHeaders: headers,
              );
        await candidate.initialize().timeout(const Duration(seconds: 25));
        return await _finishAttach(
          candidate,
          url,
          resumeAt: resumeAt,
          requestId: requestId,
        );
      } catch (e) {
        lastErr = e;
        _log('attach fail headers=${headers != null}: $e');
        try {
          await candidate?.dispose();
        } catch (_) {}
      }
    }
    if (requestId == _attachRequestId && mounted) {
      setState(() => _isBuffering = false);
    }
    throw lastErr ?? Exception('Failed to initialize stream');
  }

  Future<bool> _finishAttach(
    VideoPlayerController c,
    String url, {
    Duration? resumeAt,
    required int requestId,
  }) async {
    if (!mounted || requestId != _attachRequestId) {
      await c.dispose();
      return false;
    }
    // Capture the provider up-front: every use below sits after an await and
    // touching BuildContext across an async gap is unsafe once popped.
    final provider = context.read<AppProvider>();
    // Seek before the first play(): seeking afterwards restarts audio at 0
    // for a moment, which is what made quality switches feel like a reload.
    if (resumeAt != null && resumeAt > Duration.zero) {
      try {
        await c.seekTo(resumeAt);
      } catch (_) {}
    }
    await c.setLooping(_looping);
    await c.setPlaybackSpeed(_speed);
    await c.setVolume(_muted ? 0 : 1);
    if (!mounted || requestId != _attachRequestId) {
      await c.dispose();
      return false;
    }

    final previous = _controller;
    if (previous != null && _borrowedFromMini) {
      context.read<MiniPlayerController>().detachController();
      _borrowedFromMini = false;
    }
    previous?.removeListener(_onTick);
    c.addListener(_onTick);
    setState(() {
      _controller = c;
      _ready = true;
      _isBuffering = false;
      _activeUrl = url;
      _duration = c.value.duration;
    });
    if (previous != null && previous != c && !_handedToMini) {
      await previous.dispose();
    }
    // Give PiP the true dimensions; otherwise a Short is letterboxed into a
    // 16:9 window.
    final sz = c.value.size;
    if (sz.width > 0 && sz.height > 0) {
      NativePlayer.setVideoAspect(sz.width.round(), sz.height.round());
    }
    _requestingFocus = true;
    _lastPlayTime = DateTime.now();
    try {
      await AudioHelper.requestFocus();
      await c.play();
    } finally {
      _releaseFocusGuardSoon();
    }
    if (!mounted) return true;
    await NativePlayer.setPlaying(true);
    if (!mounted) return true;
    final title =
        provider.currentVideo?.title ?? widget.preview?.title ?? 'VibeTube';
    final artist =
        provider.currentVideo?.channelName ??
        widget.preview?.channelName ??
        'Playing';
    // Keep the screen awake while the video plays. The old code disabled the
    // wakelock whenever background play was on — and background play defaults
    // to ON — so with default settings the screen slept ~30s into every
    // video and the picture died while the audio kept going.
    // "Background play" means audio survives the screen going off, not that
    // we should hurry it along.
    await _applyWakelock(playing: true);
    if (provider.isBackgroundPlayEnabled) {
      await NativePlayer.startBackground(
        title: title,
        artist: artist,
        playing: true,
      );
      _bgActive = true;
    }
    if (!mounted) return true;
    _armHide();
    _startPosTimer();
    return true;
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.isBuffering != _isBuffering) {
      setState(() => _isBuffering = v.isBuffering);
    }
    final playing = v.isInitialized && v.isPlaying;
    if (playing != _lastNativePlaying) {
      _lastNativePlaying = playing;
      NativePlayer.setPlaying(playing);
    }
    // Guard context.read against post-dispose listener callbacks
    try {
      final live = context.read<AppProvider>().currentVideo?.isLive == true;
      if (!live) {
        _maybeSkipSponsor(v.position);
      }
    } catch (_) {
      // Widget disposed — safe to ignore
    }
  }

  void _startPosTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final c = _controller;
      if (c == null || !c.value.isInitialized || _seeking) return;
      if (!mounted) return;
      // Nothing on this screen is visible in PiP or while the app is in the
      // background, so a 4x/second setState there is pure battery drain
      // during background audio playback.
      if (_inPip || !_appResumed) return;
      // Only rebuild when controls are visible or progress bar needs updating
      final newPos = c.value.position;
      final newDur = c.value.duration;
      if (newPos == _position && newDur == _duration) return; // no change
      setState(() {
        _position = newPos;
        _duration = newDur;
      });
    });
  }

  void _maybeSkipSponsor(Duration pos) {
    if (!mounted) return;
    AppProvider provider;
    try {
      provider = context.read<AppProvider>();
    } catch (_) {
      return; // Widget disposed
    }
    if (!provider.isSponsorBlockEnabled) return;
    final t = pos.inMilliseconds / 1000.0;
    for (final seg in provider.activeSponsorSegments) {
      if (t >= seg.start && t < seg.end - 0.15) {
        final target = Duration(milliseconds: (seg.end * 1000).round());
        _controller?.seekTo(target);
        setState(() {
          _sponsorToast = true;
          _sponsorLabel = _prettyCategory(seg.category);
        });
        // A cancellable timer, not Future.delayed: back-to-back segments each
        // scheduled an independent callback, so an earlier one could hide the
        // toast for the segment currently being skipped. Holding the timer
        // also lets dispose() cancel it.
        _sponsorToastTimer?.cancel();
        _sponsorToastTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _sponsorToast = false);
        });
        break;
      }
    }
  }

  String _prettyCategory(String c) {
    switch (c) {
      case 'sponsor':
        return 'Sponsor';
      case 'selfpromo':
        return 'Self-promo';
      case 'interaction':
        return 'Interaction';
      case 'intro':
        return 'Intro';
      case 'outro':
        return 'Outro';
      case 'filler':
        return 'Filler';
      default:
        return c;
    }
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _armHide();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      _requestingFocus = true;
      try {
        await c.pause();
        _pausedByInterruption = false;
      } finally {
        _releaseFocusGuardSoon();
      }
      await _applyWakelock(playing: false);
    } else {
      _requestingFocus = true;
      _lastPlayTime = DateTime.now();
      try {
        await AudioHelper.requestFocus();
        await c.play();
      } finally {
        _releaseFocusGuardSoon();
      }
      await _applyWakelock(playing: true);
    }
    if (mounted) setState(() {});
    await _syncNativePlayback(forceBg: true);
    _armHide();
  }

  /// Debug-only logging.
  ///
  /// `debugPrint` still runs in release builds (it only rate-limits), so
  /// signed stream URLs and playback errors were being written to logcat on
  /// shipped APKs. Everything here is diagnostic, so compile it out.
  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Keeps the screen-on lock in step with playback.
  ///
  /// PiP has its own system-managed window, so we drop the lock there.
  Future<void> _applyWakelock({required bool playing}) async {
    try {
      if (playing && !_inPip) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Wakelock is best-effort; never let it break playback.
    }
  }

  /// Clears [_requestingFocus] one second after the *latest* play request.
  ///
  /// Each call used to schedule an independent `Future.delayed`, so two taps
  /// 200ms apart meant the first timer opened the guard while the second
  /// request was still settling — and the resulting focus callback paused the
  /// video the user had just started. Token check makes only the newest timer
  /// win.
  void _releaseFocusGuardSoon() {
    final token = ++_focusGuardToken;
    Future.delayed(const Duration(seconds: 1), () {
      if (token == _focusGuardToken) _requestingFocus = false;
    });
  }

  Future<void> _syncNativePlayback({bool forceBg = false}) async {
    if (!mounted) return;
    final c = _controller;
    final playing = c != null && c.value.isInitialized && c.value.isPlaying;
    // Read the provider before awaiting — context is unsafe after the gap.
    final provider = context.read<AppProvider>();
    await NativePlayer.setPlaying(playing);
    await _applyWakelock(playing: playing);
    if (!provider.isBackgroundPlayEnabled) {
      if (_bgActive) {
        await NativePlayer.stopBackground();
        _bgActive = false;
      }
      return;
    }
    final title =
        provider.currentVideo?.title ?? widget.preview?.title ?? 'VibeTube';
    final artist =
        provider.currentVideo?.channelName ??
        widget.preview?.channelName ??
        'Playing';
    if (playing) {
      if (_bgActive || forceBg) {
        await NativePlayer.updateBackground(
          title: title,
          artist: artist,
          playing: true,
        );
        _bgActive = true;
      } else {
        await NativePlayer.startBackground(
          title: title,
          artist: artist,
          playing: true,
        );
        _bgActive = true;
      }
    } else if (_bgActive) {
      await NativePlayer.updateBackground(
        title: title,
        artist: artist,
        playing: false,
      );
    }
  }

  Future<void> _seekBy(int seconds) async {
    final c = _controller;
    if (c == null) return;
    final next = c.value.position + Duration(seconds: seconds);
    final d = c.value.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > d ? d : next);
    await c.seekTo(clamped);
    _armHide();
  }

  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullscreen() async {
    setState(() => _fullscreen = false);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  /// YouTube-style: keep playing in bottom mini player.
  ///
  /// Only when something is actually playing. Backing out of a *paused* video
  /// now closes the player outright — previously every back press spawned a
  /// mini bar the user then had to hunt down and dismiss, and there was no
  /// way to leave the screen that also stopped playback.
  Future<void> _minimizeToMiniPlayer() async {
    final mini = context.read<MiniPlayerController>();
    final provider = context.read<AppProvider>();
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!c.value.isPlaying) {
      // Nothing to keep alive: tear down instead of minimising.
      mini.setExpanded(false);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final meta = provider.currentVideo;
    final preview = widget.preview;
    final v = Video(
      id: widget.videoId,
      title: meta?.title.isNotEmpty == true
          ? meta!.title
          : (preview?.title ?? 'Playing'),
      thumbnailUrl: meta?.thumbnailUrl.isNotEmpty == true
          ? meta!.thumbnailUrl
          : (preview?.thumbnailUrl ?? ''),
      channelName: meta?.channelName.isNotEmpty == true
          ? meta!.channelName
          : (preview?.channelName ?? ''),
      channelId: meta?.channelId ?? preview?.channelId ?? '',
      viewCount: meta?.viewCount ?? preview?.viewCount ?? 0,
      duration: meta?.duration ?? preview?.duration ?? Duration.zero,
      publishedAt: meta?.publishedAt ?? preview?.publishedAt ?? '',
    );

    // Detach listeners so dispose won't fight mini
    c.removeListener(_onTick);
    _posTimer?.cancel();
    _hideTimer?.cancel();
    _handedToMini = true;
    _controller = null;

    final wasPlaying = c.value.isPlaying;
    mini.adopt(
      ctrl: c,
      video: v,
      details: meta,
      activeUrl: _activeUrl,
      quality: _quality,
      speed: _speed,
    );
    await NativePlayer.setPlaying(wasPlaying);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    if (resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attachRequestId++;
    _playbackRequestId++;
    _hideTimer?.cancel();
    _posTimer?.cancel();
    _toastTimer?.cancel();
    _sponsorToastTimer?.cancel();
    NativePlayer.removeHandlers(
      onPip: _onPipChanged,
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
      onMediaRewind: _onMediaRewind,
      onMediaForward: _onMediaForward,
    );
    AudioHelper.removeListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
    );
    // Never dispose a controller we don't own: it was either handed to the
    // mini player on the way out, or borrowed from it on the way in
    // (resumeSession). Disposing it would leave the mini bar holding a dead
    // controller and crash on the next frame.
    final ownsController = !_handedToMini && !_borrowedFromMini;
    if (ownsController) {
      _controller?.removeListener(_onTick);
      _controller?.dispose();
      _controller = null;
      WakelockPlus.disable();
      NativePlayer.setPlaying(false);
      if (_bgActive) {
        NativePlayer.stopBackground();
        _bgActive = false;
      }
      // Release audio focus so other apps can play audio
      AudioHelper.abandonFocus();
    } else {
      _controller?.removeListener(_onTick);
      _controller = null;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In Picture-in-Picture the window is tiny: render only the video surface.
    // Controls / info pane would be unreadable and steal taps from the system.
    if (_inPip) {
      final c = _controller;
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: (_ready && c != null && c.value.isInitialized)
              ? AspectRatio(
                  aspectRatio: c.value.aspectRatio > 0
                      ? c.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(c),
                )
              : const ColoredBox(color: Colors.black),
        ),
      );
    }

    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildPlayer(fullscreen: true)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _minimizeToMiniPlayer();
      },
      child: Scaffold(
        backgroundColor: VibeColors.of(context).background,
        body: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final video = provider.currentVideo;
            final preview = widget.preview;

            return Column(
              children: [
                SafeArea(bottom: false, child: _buildPlayer(fullscreen: false)),
                Expanded(
                  child: provider.isPlayerLoading && video == null
                      ? const Center(child: CircularProgressIndicator())
                      : provider.playerError != null && video == null
                      ? _errorPane(provider)
                      : _infoPane(provider, video, preview),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _errorPane(AppProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(
              provider.playerError ?? 'Playback error',
              textAlign: TextAlign.center,
              style: TextStyle(color: VibeColors.of(context).textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await provider.loadVideoDetails(widget.videoId);
                final d = provider.currentVideo;
                if (d != null) await _startPlayback(d);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer({required bool fullscreen}) {
    final c = _controller;
    final playing = c?.value.isPlaying == true;
    final providerMeta = context.read<AppProvider>().currentVideo;
    final isShort =
        providerMeta?.isShort == true || widget.preview?.isShort == true;
    final aspect =
        (c != null && c.value.isInitialized && c.value.aspectRatio > 0)
        ? c.value.aspectRatio
        : (isShort ? 9 / 16 : 16 / 9);

    final player = GestureDetector(
      onTap: _toggleControls,
      onDoubleTapDown: (d) {
        final w = MediaQuery.sizeOf(context).width;
        if (d.localPosition.dx < w / 2) {
          _seekBy(-10);
        } else {
          _seekBy(10);
        }
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_ready && c != null)
              AspectRatio(aspectRatio: aspect, child: VideoPlayer(c))
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.preview?.thumbnailUrl.isNotEmpty == true)
                      CachedNetworkImage(
                        imageUrl: widget.preview!.thumbnailUrl,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(color: Colors.black),
                    Container(color: Colors.black45),
                  ],
                ),
              ),
            if (_isBuffering ||
                (!_ready && context.watch<AppProvider>().isPlayerLoading))
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            // Controls overlay - must be direct child of Stack (Positioned.fill)
            if (_showControls) _controlsOverlay(playing, fullscreen),
            if (_sponsorToast)
              Positioned(
                bottom: fullscreen ? 72 : 56,
                child: AnimatedOpacity(
                  opacity: _sponsorToast ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.sbSponsor.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.skip_next,
                          size: 16,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_sponsorLabel skipped',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Slim seek indicator while the controls are hidden. When they are
            // visible the full slider lives inside the bottom cluster, so
            // drawing it here too would stack two bars on the same strip.
            if (_ready && !_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _idleProgressBar(),
              ),
            // Caption overlay
            Consumer<AppProvider>(
              builder: (context, provider, _) {
                if (!provider.isCaptionsEnabled ||
                    provider.captionCues.isEmpty) {
                  return const SizedBox.shrink();
                }
                return CaptionOverlay(
                  cues: provider.captionCues,
                  position: _position,
                  visible: true,
                );
              },
            ),
            if (_toastMsg != null)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _toastMsg!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (fullscreen) {
      return Center(child: player);
    }
    return player;
  }

  Widget _controlsOverlay(bool playing, bool fullscreen) {
    final detailsIsLive =
        context.read<AppProvider>().currentVideo?.isLive == true ||
        widget.preview?.isLive == true;
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.82),
            ],
            // Bottom scrim starts higher because the cluster below is taller
            // than the title bar above it.
            stops: const [0, 0.28, 0.5, 1],
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 2, right: 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: fullscreen ? 'Exit fullscreen' : 'Minimise',
                      icon: Icon(
                        fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: fullscreen ? 24 : 30,
                      ),
                      onPressed: () async {
                        if (fullscreen) {
                          await _exitFullscreen();
                        } else {
                          await _minimizeToMiniPlayer();
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        context.watch<AppProvider>().currentVideo?.title ??
                            widget.preview?.title ??
                            '',
                        maxLines: fullscreen ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.25,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    if (context.watch<AppProvider>().isSponsorBlockEnabled)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: 'SponsorBlock active',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.sbSponsor.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'SB',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _centreBtn(
                  Icons.replay_10,
                  'Back 10 seconds',
                  () => _seekBy(-10),
                  30,
                ),
                const SizedBox(width: 28),
                _centreBtn(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  playing ? 'Pause' : 'Play',
                  _togglePlay,
                  40,
                  primary: true,
                ),
                const SizedBox(width: 28),
                _centreBtn(
                  Icons.forward_10,
                  'Forward 10 seconds',
                  () => _seekBy(10),
                  30,
                ),
              ],
            ),
            const Spacer(),
            // Bottom cluster: scrubber, then time + transport, then actions.
            // Each row has one job so the controls stop reading as one blob.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Scrubber sits directly under the video, full width.
                  if (_ready && !detailsIsLive) _progressBar(),

                  // 2. Elapsed time on the left, playback settings on the
                  //    right — the controls that change *how* it plays.
                  SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        if (detailsIsLive)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF3B30),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Color(0xFFFF5555),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            '${_fmt(_position)} / ${_fmt(_duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        const Spacer(),
                        _ctrlIcon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          'Mute',
                          _toggleMute,
                          active: _muted,
                        ),
                        _ctrlIcon(
                          _looping ? Icons.repeat_one : Icons.repeat,
                          'Loop',
                          _toggleLoop,
                          active: _looping,
                        ),
                        _pillBtn(_speedLabel, _showSpeedSheet),
                        if (!detailsIsLive)
                          _pillBtn(
                            _quality.replaceAll(' (HLS)', ''),
                            _showQualitySheet,
                          ),
                        if (_pipSupported)
                          _ctrlIcon(
                            Icons.picture_in_picture_alt_outlined,
                            'PiP',
                            _enterPipIfPlaying,
                          ),
                        _ctrlIcon(
                          fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                          () async {
                            if (fullscreen) {
                              await _exitFullscreen();
                            } else {
                              await _enterFullscreen();
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // 3. Actions on the video itself. Hidden in fullscreen,
                  //    where the same actions are a swipe away in the info
                  //    pane and screen space is better spent on the picture.
                  if (!fullscreen) ...[
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        children: [
                          _chipBtn(Icons.skip_next, 'Next', _playNextRelated),
                          _chipBtn(
                            _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                            'Like',
                            _toggleLike,
                            active: _liked,
                          ),
                          _chipBtn(
                            Icons.thumb_down_outlined,
                            'Dislike',
                            _showDislikes,
                          ),
                          _chipBtn(Icons.share_outlined, 'Share', _shareVideo),
                          _chipBtn(
                            _watchLater
                                ? Icons.watch_later
                                : Icons.watch_later_outlined,
                            'Save',
                            _toggleWatchLater,
                            active: _watchLater,
                          ),
                          _chipBtn(
                            Icons.download_outlined,
                            'Download',
                            _downloadCurrent,
                          ),
                          _chipBtn(
                            context.watch<AppProvider>().isCaptionsEnabled
                                ? Icons.closed_caption
                                : Icons.closed_caption_outlined,
                            'CC',
                            _showCaptionSheet,
                            active: context
                                .watch<AppProvider>()
                                .isCaptionsEnabled,
                          ),
                          _chipBtn(Icons.headphones, 'Audio', _audioOnlyMode),
                          _chipBtn(
                            Icons.settings_outlined,
                            'More',
                            _showMoreSheet,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Circular transport button with a scrim so the glyph stays readable
  /// over bright frames.
  Widget _centreBtn(
    IconData icon,
    String tip,
    VoidCallback onTap,
    double size, {
    bool primary = false,
  }) {
    final diameter = primary ? 64.0 : 48.0;
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.black.withValues(alpha: primary ? 0.38 : 0.28),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }

  /// Compact text button used for speed / quality in the control row.
  Widget _pillBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _speedLabel {
    final s = _speed == _speed.roundToDouble()
        ? _speed.toInt().toString()
        : _speed.toString();
    return '${s}x';
  }

  /// Thin, non-interactive progress line shown while the controls are
  /// hidden, so the user still has a sense of position without a full slider
  /// (and without a stray thumb floating over the video).
  Widget _idleProgressBar() {
    final total = _duration.inMilliseconds;
    if (total <= 0) return const SizedBox.shrink();
    final value = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return IgnorePointer(
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2.5,
        backgroundColor: Colors.white24,
        valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
      ),
    );
  }

  Widget _progressBar() {
    final total = _duration.inMilliseconds.toDouble().clamp(1, double.infinity);
    final value = _seeking
        ? _seekValue
        : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    final segments = context.read<AppProvider>().activeSponsorSegments;

    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sponsor segments, drawn on the same centre line as the track so
          // they read as part of the bar rather than a stripe above it.
          if (_duration.inMilliseconds > 0 && segments.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  // Match the Slider's own horizontal inset so markers line
                  // up with the track instead of drifting at the edges.
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return Stack(
                        alignment: Alignment.center,
                        children: segments.map((s) {
                          final left = ((s.start * 1000 / total) * box.maxWidth)
                              .clamp(0.0, box.maxWidth);
                          // Clamp the width against the *remaining* space:
                          // clamping both independently let an outro segment
                          // near the end paint past the right edge.
                          final available = (box.maxWidth - left).clamp(0.0, box.maxWidth);
                          final width =
                              (((s.end - s.start) * 1000 / total) * box.maxWidth)
                                  .clamp(0.0, available);
                          if (width <= 0) return const SizedBox.shrink();
                          return Positioned(
                            left: left,
                            width: width < 2 ? (available < 2 ? available : 2) : width,
                            height: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.sbSponsor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppTheme.primary,
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: value.isNaN ? 0 : value,
              onChangeStart: (_) {
                setState(() {
                  _seeking = true;
                  _seekValue = value;
                });
              },
              onChanged: (v) => setState(() => _seekValue = v),
              onChangeEnd: (v) async {
                final target = Duration(milliseconds: (v * total).round());
                await _controller?.seekTo(target);
                setState(() {
                  _seeking = false;
                  _position = target;
                });
                _armHide();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPane(AppProvider provider, VideoDetails? video, Video? preview) {
    final c = VibeColors.of(context);
    final title = video?.title ?? preview?.title ?? 'Loading…';
    final channel = video?.channelName ?? preview?.channelName ?? '';
    final views =
        video?.formattedViewCount ?? preview?.formattedViewCount ?? '0';
    final published = video?.publishedAt ?? preview?.publishedAt ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        if (video?.isLive == true || preview?.isLive == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Streaming live',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        if (video?.isShort == true || preview?.isShort == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.movie_filter_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Shorts',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            if ((video?.viewCount ?? preview?.viewCount ?? 0) > 0)
              '$views views',
            if (published.isNotEmpty) published,
          ].join(' · '),
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              _action(
                icon: _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                label: video != null && video.likeCount > 0
                    ? _short(video.likeCount)
                    : 'Like',
                active: _liked,
                onTap: () async {
                  final v = video ?? preview;
                  if (v == null) return;
                  final now = await provider.toggleLike(v);
                  setState(() => _liked = now);
                },
              ),
              _action(
                icon: Icons.thumb_down_outlined,
                label: (provider.dislikeCount ?? _dislikes) != null
                    ? _short((provider.dislikeCount ?? _dislikes)!)
                    : 'Dislike',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (provider.dislikeCount ?? _dislikes) != null
                            ? '${provider.dislikeCount ?? _dislikes} dislikes (Return YouTube Dislike)'
                            : 'Dislike count unavailable',
                      ),
                    ),
                  );
                },
              ),
              _action(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Share.share(
                    ShareLinks.shareText(widget.videoId, title),
                    subject: title,
                  );
                },
              ),
              _action(
                icon: Icons.watch_later_outlined,
                label: 'Save',
                onTap: () async {
                  final v = video ?? preview;
                  if (v == null) return;
                  final added = await provider.toggleWatchLater(v);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        added
                            ? 'Saved to Watch Later'
                            : 'Removed from Watch Later',
                      ),
                    ),
                  );
                },
              ),
              _action(
                icon: Icons.download_outlined,
                label: provider.downloadingIds.contains(widget.videoId)
                    ? '${((provider.downloadProgress[widget.videoId] ?? 0) * 100).toStringAsFixed(0)}%'
                    : 'Download',
                onTap: () async {
                  final v = video ?? preview;
                  if (v == null) return;
                  if (provider.downloadingIds.contains(v.id)) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Downloading…')));
                  try {
                    await provider.downloadVideo(v);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Download complete — open Downloads tab'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Download failed: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Channel row: avatar, name, subscribe. No card border — the avatar
        // and button already give it enough shape.
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.surfaceVariant,
              child: Text(
                initialLetter(channel, fallback: 'C'),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.isEmpty ? 'Channel' : channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: c.textPrimary,
                    ),
                  ),
                  if (video != null && video.likeCount > 0)
                    Text(
                      '${_short(video.likeCount)} likes',
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _toggleSubscribe(channel);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(_subscribed ? 'Subscribed' : 'Subscribe'),
            ),
          ],
        ),
        if ((video?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video?.description ?? '',
                    maxLines: _descExpanded ? 1000 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _descExpanded ? 'Show less' : 'Show more',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        // SponsorBlock card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.skip_next, color: AppTheme.sbSponsor),
            title: Text(
              'SponsorBlock',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              provider.sponsorSegments.isEmpty
                  ? 'Auto-skip sponsored segments'
                  : '${provider.activeSponsorSegments.length} segments loaded',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            value: provider.isSponsorBlockEnabled,
            onChanged: (_) => provider.toggleSponsorBlock(),
          ),
        ),
        if (provider.comments.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'Comments · ${provider.comments.length}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...provider.comments.take(8).map(_commentTile),
        ],
        if (provider.relatedVideos.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'Related',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...provider.relatedVideos.take(15).map((v) {
            return VideoCard(
              video: v,
              compact: true,
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(videoId: v.id, preview: v),
                  ),
                );
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _commentTile(Comment comment) {
    final col = VibeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: col.surfaceVariant,
            backgroundImage: comment.authorAvatar.isNotEmpty
                ? CachedNetworkImageProvider(comment.authorAvatar)
                : null,
            child: comment.authorAvatar.isEmpty
                ? Text(
                    initialLetter(comment.author, fallback: '?'),
                    style: TextStyle(fontSize: 12, color: col.textPrimary),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comment.author} · ${comment.publishedAt}',
                  style: TextStyle(fontSize: 11, color: col.textMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: col.textPrimary,
                  ),
                ),
                if (comment.likeCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        size: 12,
                        color: col.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _short(comment.likeCount),
                        style: TextStyle(fontSize: 11, color: col.textMuted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final col = VibeColors.of(context);
    final fg = active ? AppTheme.primary : col.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active
            ? AppTheme.primary.withValues(alpha: 0.14)
            : col.surfaceLight,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final speeds = [
      0.25,
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      1.75,
      2.0,
      2.25,
      2.5,
      2.75,
      3.0,
    ];
    final c = VibeColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SafeArea(
          child: SizedBox(
            height: h * 0.55,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Playback speed',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_speed}x',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: speeds.length,
                    itemBuilder: (_, i) {
                      final s = speeds[i];
                      final selected = (_speed - s).abs() < 0.001;
                      return ListTile(
                        title: Text(
                          '${s}x',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: s == 1.0
                            ? Text(
                                'Normal',
                                style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        trailing: selected
                            ? const Icon(Icons.check, color: AppTheme.primary)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          // Session-only, like quality above. The global
                          // default lives in Settings.
                          setState(() => _speed = s);
                          await _controller?.setPlaybackSpeed(s);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQualitySheet() {
    final details = context.read<AppProvider>().currentVideo;
    if (details?.isLive == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live streams use adaptive HLS quality automatically'),
        ),
      );
      return;
    }
    final qs =
        details?.availableQualities ??
        ['Auto (HLS)', '1080p', '720p', '480p', '360p', 'Audio Only'];
    final hasHls = details?.hlsUrl != null && details!.hlsUrl!.isNotEmpty;
    final c = VibeColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SafeArea(
          child: SizedBox(
            height: h * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        'Quality',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _quality,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    (details?.hlsVariants.isNotEmpty == true)
                        ? '${details!.hlsVariants.length} stream(s) · up to ${_maxQualityLabel(details)}'
                        : (hasHls
                              ? 'HLS master only · try Auto'
                              : 'Only progressive (often 360p)'),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: qs.length,
                    itemBuilder: (_, i) {
                      final q = qs[i];
                      final selected = _quality == q;
                      final String sub;
                      final d = details;
                      if (q.startsWith('Auto')) {
                        final maxQ = _maxQualityLabel(d);
                        sub = hasHls
                            ? 'Adaptive · up to $maxQ'
                            : 'Best progressive';
                      } else if (q == 'Audio Only') {
                        sub = 'Audio track';
                      } else {
                        final h =
                            int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ??
                            0;
                        final hasExact =
                            d != null &&
                            (d.hlsVariants.containsKey(h) ||
                                d.progressiveByHeight.containsKey(h));
                        final hasNear =
                            d != null &&
                            (d.hlsVariants.keys.any(
                                  (x) => (x - h).abs() <= 20,
                                ) ||
                                d.progressiveByHeight.keys.any(
                                  (x) => (x - h).abs() <= 20,
                                ));
                        if (hasExact || hasNear) {
                          // hasExact/hasNear are only true when d != null.
                          final isHls =
                              d.hlsVariants.containsKey(h) ||
                              d.hlsVariants.keys.any(
                                (x) => (x - h).abs() <= 20,
                              );
                          sub = isHls
                              ? 'Tap to lock · HLS'
                              : 'Tap to lock · MP4';
                        } else if (hasHls) {
                          sub = 'via nearest HLS';
                        } else {
                          sub = 'May fallback';
                        }
                      }
                      return ListTile(
                        title: Text(
                          q,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          sub,
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check, color: AppTheme.primary)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          // Session-only. Changing one video's quality used to
                          // overwrite the app-wide default, so a one-off 360p
                          // pick on a weak connection silently became the
                          // setting for every future video.
                          setState(() => _quality = q);
                          final d = context.read<AppProvider>().currentVideo;
                          if (d != null) {
                            final pos = _controller?.value.position;
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Switching to $q…'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                            // resumeAt seeks before the first play(), so the
                            // switch continues from where we were.
                            await _startPlayback(d, quality: q, resumeAt: pos);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ctrlIcon(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Icon(
            icon,
            color: active ? AppTheme.primary : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _chipBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active
            ? AppTheme.primary.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? AppTheme.primary : Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? AppTheme.primary : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toastMsg = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    setState(() => _muted = !_muted);
    await c.setVolume(_muted ? 0 : 1);
    _toast(_muted ? 'Muted' : 'Unmuted');
  }

  Future<void> _toggleLoop() async {
    setState(() => _looping = !_looping);
    await _controller?.setLooping(_looping);
    _toast(_looping ? 'Loop on' : 'Loop off');
  }

  Future<void> _enterPipIfPlaying() async {
    if (_controller?.value.isPlaying != true) {
      _toast('Play the video to use PiP');
      return;
    }
    await NativePlayer.setPlaying(true);
    final ok = await NativePlayer.enterPip();
    if (!ok) {
      _toast(_pipSupported ? 'PiP unavailable' : 'PiP not supported');
    }
  }

  void _toggleSubscribe(String channel) {
    setState(() => _subscribed = !_subscribed);
    _toast(_subscribed ? "Subscribed to $channel" : "Unsubscribed");
  }

  Future<void> _toggleLike() async {
    final provider = context.read<AppProvider>();
    final meta = provider.currentVideo;
    final preview = widget.preview;
    final v = Video(
      id: widget.videoId,
      title: meta?.title ?? preview?.title ?? '',
      thumbnailUrl: meta?.thumbnailUrl ?? preview?.thumbnailUrl ?? '',
      channelName: meta?.channelName ?? preview?.channelName ?? '',
      channelId: meta?.channelId ?? preview?.channelId ?? '',
      viewCount: meta?.viewCount ?? preview?.viewCount ?? 0,
      duration: meta?.duration ?? preview?.duration ?? Duration.zero,
      isLive: meta?.isLive ?? preview?.isLive ?? false,
      isShort: meta?.isShort ?? preview?.isShort ?? false,
    );
    final liked = await provider.toggleLike(v);
    if (!mounted) return;
    setState(() => _liked = liked);
    _toast(liked ? 'Added to Liked' : 'Removed like');
  }

  Future<void> _toggleWatchLater() async {
    final provider = context.read<AppProvider>();
    final meta = provider.currentVideo;
    final preview = widget.preview;
    final v = Video(
      id: widget.videoId,
      title: meta?.title ?? preview?.title ?? '',
      thumbnailUrl: meta?.thumbnailUrl ?? preview?.thumbnailUrl ?? '',
      channelName: meta?.channelName ?? preview?.channelName ?? '',
      channelId: meta?.channelId ?? preview?.channelId ?? '',
      viewCount: meta?.viewCount ?? preview?.viewCount ?? 0,
      duration: meta?.duration ?? preview?.duration ?? Duration.zero,
      isLive: meta?.isLive ?? preview?.isLive ?? false,
      isShort: meta?.isShort ?? preview?.isShort ?? false,
    );
    final saved = await provider.toggleWatchLater(v);
    if (!mounted) return;
    setState(() => _watchLater = saved);
    _toast(saved ? 'Saved to Watch Later' : 'Removed');
  }

  void _showDislikes() {
    // Side data (dislikes) resolves after loadVideoDetails returns, so the
    // `_dislikes` snapshot taken in _boot() was essentially always null.
    final n = context.read<AppProvider>().dislikeCount ?? _dislikes;
    _toast(n == null ? 'Dislike count unavailable' : '${_short(n)} dislikes');
  }

  Future<void> _shareVideo() async {
    final title =
        context.read<AppProvider>().currentVideo?.title ??
        widget.preview?.title ??
        'VibeTube';
    await Share.share(
      ShareLinks.shareText(widget.videoId, title),
      subject: title,
    );
  }

  Future<void> _downloadCurrent() async {
    final provider = context.read<AppProvider>();
    if (provider.currentVideo?.isLive == true) {
      _toast('Cannot download live streams');
      return;
    }
    final meta = provider.currentVideo;
    final preview = widget.preview;
    final v = Video(
      id: widget.videoId,
      title: meta?.title ?? preview?.title ?? 'Video',
      thumbnailUrl: meta?.thumbnailUrl ?? preview?.thumbnailUrl ?? '',
      channelName: meta?.channelName ?? preview?.channelName ?? '',
      duration: meta?.duration ?? preview?.duration ?? Duration.zero,
    );
    _toast('Downloading…');
    try {
      await provider.downloadVideo(v);
      if (mounted) _toast('Download complete');
    } catch (_) {
      if (mounted) _toast('Download failed');
    }
  }

  Future<void> _audioOnlyMode() async {
    final d = context.read<AppProvider>().currentVideo;
    if (d == null) return;
    if (d.isLive) {
      _toast('Not available on live');
      return;
    }
    setState(() => _quality = 'Audio Only');
    final pos = _controller?.value.position;
    await _startPlayback(d, quality: 'Audio Only', resumeAt: pos);
    _toast('Audio only');
  }

  int _nextRelatedIndex = 0;

  void _playNextRelated() {
    final related = context.read<AppProvider>().relatedVideos;
    if (related.isEmpty) {
      _toast('No related videos');
      return;
    }
    // Advance through the list; tapping Next twice used to reopen the same
    // video because it always took `related.first`.
    if (_nextRelatedIndex >= related.length) _nextRelatedIndex = 0;
    final next = related[_nextRelatedIndex];
    _nextRelatedIndex++;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(videoId: next.id, preview: next),
      ),
    );
  }

  void _showCaptionSheet() {
    final provider = context.read<AppProvider>();
    final c = VibeColors.of(context);

    if (provider.captionTracks.isEmpty) {
      _toast('No captions available for this video');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SafeArea(
          child: SizedBox(
            height: h * 0.5,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.closed_caption,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Captions',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: provider.isCaptionsEnabled,
                        onChanged: (_) {
                          provider.toggleCaptions();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Off option
                ListTile(
                  leading: Icon(
                    Icons.closed_caption_disabled,
                    color: c.textSecondary,
                  ),
                  title: Text(
                    'Off',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: !provider.isCaptionsEnabled
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: !provider.isCaptionsEnabled
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    provider.toggleCaptions();
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(height: 1),
                // Available tracks
                Expanded(
                  child: ListView.builder(
                    itemCount: provider.captionTracks.length,
                    itemBuilder: (_, i) {
                      final track = provider.captionTracks[i];
                      final selected =
                          provider.isCaptionsEnabled &&
                          provider.selectedCaptionLanguage ==
                              track.languageCode;
                      return ListTile(
                        leading: Icon(
                          Icons.closed_caption,
                          color: selected ? AppTheme.primary : c.textSecondary,
                        ),
                        title: Text(
                          track.name,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: track.isAutoGenerated
                            ? Text(
                                'Auto-generated',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textMuted,
                                ),
                              )
                            : null,
                        trailing: selected
                            ? const Icon(Icons.check, color: AppTheme.primary)
                            : null,
                        onTap: () async {
                          if (!provider.isCaptionsEnabled) {
                            provider.toggleCaptions();
                          }
                          await provider.selectCaptionTrack(track);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _toast('Captions: ${track.name}');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMoreSheet() {
    final c = VibeColors.of(context);
    final provider = context.read<AppProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              secondary: Icon(Icons.headphones, color: c.textPrimary),
              title: Text(
                'Background play',
                style: TextStyle(color: c.textPrimary),
              ),
              subtitle: Text(
                'Keep audio when screen is off (media notification)',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
              value: provider.isBackgroundPlayEnabled,
              onChanged: (_) async {
                provider.toggleBackgroundPlay();
                Navigator.pop(ctx);
                if (provider.isBackgroundPlayEnabled) {
                  unawaited(ensureNotificationPermission());
                  await AudioHelper.requestFocus();
                  await _syncNativePlayback(forceBg: true);
                  _toast('Background play ON — lock phone to test');
                } else {
                  await NativePlayer.stopBackground();
                  _bgActive = false;
                  _toast('Background play OFF');
                }
              },
            ),
            SwitchListTile(
              secondary: Icon(
                Icons.picture_in_picture_alt,
                color: c.textPrimary,
              ),
              title: Text('Auto PiP', style: TextStyle(color: c.textPrimary)),
              value: provider.isAutoPipEnabled,
              onChanged: (_) {
                provider.toggleAutoPip();
                Navigator.pop(ctx);
              },
            ),
            SwitchListTile(
              secondary: Icon(Icons.skip_next, color: c.textPrimary),
              title: Text(
                'SponsorBlock',
                style: TextStyle(color: c.textPrimary),
              ),
              value: provider.isSponsorBlockEnabled,
              onChanged: (_) {
                provider.toggleSponsorBlock();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new, color: c.textPrimary),
              title: Text(
                'Share YouTube link',
                style: TextStyle(color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _shareVideo();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _maxQualityLabel(VideoDetails? d) {
    if (d == null) return '720p';
    final hs = <int>[...d.hlsVariants.keys, ...d.progressiveByHeight.keys];
    if (hs.isEmpty) {
      return (d.hlsUrl != null && d.hlsUrl!.isNotEmpty) ? '1080p' : '360p';
    }
    hs.sort();
    final h = hs.last;
    if (h >= 2160) return '2160p';
    if (h >= 1440) return '1440p';
    if (h >= 1080) return '1080p';
    if (h >= 720) return '720p';
    if (h >= 480) return '480p';
    return '${h}p';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '${d.inMinutes}:$s';
  }

  String _short(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
