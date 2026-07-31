import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/video.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import '../services/native_player.dart';
import '../services/audio_helper.dart';
import '../providers/mini_player_controller.dart';

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

class _PlayerScreenState extends State<PlayerScreen> {
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
  bool _resumed = false;
  bool _lastNativePlaying = false;
  bool _looping = false;
  bool _muted = false;
  bool _watchLater = false;
  String? _toastMsg;
  Timer? _toastTimer;

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

  void _onPipChanged(bool inPip) {
    if (!mounted) return;
    setState(() => _inPip = inPip);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _boot();
  }

  Future<void> _boot() async {
    final provider = context.read<AppProvider>();
    final mini = context.read<MiniPlayerController>();
    mini.setExpanded(true);

    _speed = provider.defaultSpeed;
    _quality = provider.defaultQuality.isEmpty ? 'Auto (HLS)' : provider.defaultQuality;
    if (_quality == 'Auto') _quality = 'Auto (HLS)';
    _liked = await provider.isLiked(widget.videoId);
    try {
      _watchLater = provider.watchLater.any((e) => e.id == widget.videoId);
    } catch (_) {}
    _pipSupported = await NativePlayer.isPipSupported();
    await NativePlayer.setAutoPip(provider.isAutoPipEnabled);
    await NativePlayer.setPlaying(false);
    NativePlayer.ensureHandlers(
      onPip: _onPipChanged,
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );

    // Resume from mini player — same controller, no reload
    if (widget.resumeSession &&
        mini.hasSession &&
        mini.video?.id == widget.videoId &&
        mini.controller != null &&
        mini.controller!.value.isInitialized) {
      _resumed = true;
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
        debugPrint('local play failed: $e');
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

  Future<void> _startPlayback(VideoDetails details, {String? quality}) async {
    final q = (details.isLive)
        ? 'Auto (HLS)'
        : (quality ?? _quality);
    // Live streams require HLS / DASH — force Auto HLS path


    final candidates = <String>[];
    void add(String? u) {
      if (u != null && u.isNotEmpty && !candidates.contains(u)) {
        candidates.add(u);
      }
    }

    final isAuto = details.isLive ||
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
      add(details.hlsUrl);
      if (details.hlsVariants.isNotEmpty) {
        final hs = details.hlsVariants.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final prefer in [1080, 720, 480, 1440, 2160]) {
          if (details.hlsVariants.containsKey(prefer)) {
            add(details.hlsVariants[prefer]);
          }
        }
        for (final h in hs) {
          add(details.hlsVariants[h]);
        }
      }
      add(details.preferredPlayUrl);
      add(details.bestMuxedUrl);
    } else if (q == 'Audio Only') {
      add(details.urlForQuality(q));
      add(details.bestMuxedUrl);
    } else {
      // Locked quality — NEVER silently jump to unrelated 360p first
      add(details.urlForQuality(q));
      if (target > 0) {
        // exact + nearest HLS
        final hHeights = details.hlsVariants.keys.toList()
          ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
        for (final h in hHeights) {
          add(details.hlsVariants[h]);
        }
        final pHeights = details.progressiveByHeight.keys.toList()
          ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
        for (final h in pHeights) {
          add(details.progressiveByHeight[h]);
        }
      }
      // master HLS as soft fallback (adaptive)
      add(details.hlsUrl);
      // progressive only if nothing else
      add(details.bestMuxedUrl);
    }

    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _isBuffering = false;
          _ready = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable stream for this video')),
        );
      }
      return;
    }

    debugPrint(
        'Quality=$q candidates=${candidates.length} hlsVars=${details.hlsVariants.keys.toList()} prog=${details.progressiveByHeight.keys.toList()} hlsMaster=${details.hlsUrl != null}');

    Object? lastErr;
    for (final url in candidates) {
      try {
        await _attachController(url);
        if (_ready) {
          final tag = url.contains('m3u8')
              ? (url == details.hlsUrl ? 'HLS-master' : 'HLS-variant')
              : 'MP4';
          debugPrint('Playing $q via $tag');
          if (mounted) setState(() {}); // refresh quality label if needed
          return;
        }
      } catch (e) {
        lastErr = e;
        debugPrint('candidate failed: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isBuffering = false;
        _ready = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playback failed ($q): $lastErr')),
      );
    }
  }

  Future<void> _attachController(String url) async {
    setState(() {
      _isBuffering = true;
      _ready = false;
    });

    final prev = _controller;
    _controller = null;
    // Only dispose previous if it wasn't handed off to the mini player
    if (!_handedToMini) {
      await prev?.dispose();
    }

    final isLocal = url.startsWith('/') || url.startsWith('file:');
    final isHls = url.contains('m3u8') || url.contains('/manifest/hls');

    if (isLocal) {
      final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
      final c = VideoPlayerController.file(File(path));
      await c.initialize().timeout(const Duration(seconds: 20));
      await _finishAttach(c, url);
      return;
    }

    // Header sets to try (order matters).
    // HLS from YouTube IOS client often needs IOS UA; Android UA can fail or degrade.
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
      // bare — some CDNs hate extra headers
      null,
      // browser-like
      {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      },
    ];

    Object? lastErr;
    for (final headers in headerSets) {
      VideoPlayerController? c;
      try {
        c = headers == null
            ? VideoPlayerController.networkUrl(Uri.parse(url))
            : VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: headers);
        await c.initialize().timeout(const Duration(seconds: 25));
        await _finishAttach(c, url);
        return;
      } catch (e) {
        lastErr = e;
        debugPrint('attach fail headers=${headers != null}: $e');
        try {
          await c?.dispose();
        } catch (_) {}
      }
    }
    throw lastErr ?? Exception('Failed to open stream');
  }

  Future<void> _finishAttach(VideoPlayerController c, String url) async {
    if (!mounted) {
      await c.dispose();
      return;
    }
    await c.setLooping(_looping);
    await c.setPlaybackSpeed(_speed);
    await c.setVolume(_muted ? 0 : 1);
    c.addListener(_onTick);
    setState(() {
      _controller = c;
      _ready = true;
      _isBuffering = false;
      _activeUrl = url;
      _duration = c.value.duration;
    });
    await AudioHelper.requestFocus();
    await c.play();
    if (!mounted) return;
    await NativePlayer.setPlaying(true);
    final provider = context.read<AppProvider>();
    final title =
        provider.currentVideo?.title ?? widget.preview?.title ?? 'VibeTube';
    final artist = provider.currentVideo?.channelName ??
        widget.preview?.channelName ??
        'Playing';
    if (provider.isBackgroundPlayEnabled) {
      // Screen can turn off; MediaSession keeps audio on system output.
      WakelockPlus.disable();
      await NativePlayer.startBackground(
        title: title,
        artist: artist,
        playing: true,
      );
      _bgActive = true;
    } else {
      WakelockPlus.enable();
    }
    if (!mounted) return;
    _armHide();
    _startPosTimer();
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
        Future.delayed(const Duration(seconds: 2), () {
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
    if (c == null) return;
    final provider = context.read<AppProvider>();
    if (c.value.isPlaying) {
      await c.pause();
      WakelockPlus.disable();
    } else {
      await AudioHelper.requestFocus();
      await c.play();
      if (!provider.isBackgroundPlayEnabled) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
    setState(() {});
    await _syncNativePlayback(forceBg: true);
    _armHide();
  }

  Future<void> _syncNativePlayback({bool forceBg = false}) async {
    final c = _controller;
    final playing = c != null && c.value.isInitialized && c.value.isPlaying;
    await NativePlayer.setPlaying(playing);
    final provider = context.read<AppProvider>();
    if (!provider.isBackgroundPlayEnabled) {
      if (_bgActive) {
        await NativePlayer.stopBackground();
        _bgActive = false;
      }
      return;
    }
    // Background mode: never hold wakelock (allows screen off)
    WakelockPlus.disable();
    final title = provider.currentVideo?.title ??
        widget.preview?.title ??
        'VibeTube';
    final artist = provider.currentVideo?.channelName ??
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
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// YouTube-style: keep playing in bottom mini player.
  Future<void> _minimizeToMiniPlayer() async {
    final mini = context.read<MiniPlayerController>();
    final provider = context.read<AppProvider>();
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
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
  void dispose() {
    _hideTimer?.cancel();
    _posTimer?.cancel();
    _toastTimer?.cancel();
    NativePlayer.removeHandlers(
      onPip: _onPipChanged,
      onMediaPlay: _onMediaPlay,
      onMediaPause: _onMediaPause,
      onMediaStop: _onMediaStop,
    );
    if (!_handedToMini) {
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
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: AppTheme.background,
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final video = provider.currentVideo;
          final preview = widget.preview;

          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: _buildPlayer(fullscreen: false),
              ),
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
              style: const TextStyle(color: AppTheme.textSecondary),
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
    final isShort = providerMeta?.isShort == true ||
        widget.preview?.isShort == true;
    final aspect = (c != null && c.value.isInitialized && c.value.aspectRatio > 0)
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
            if (_isBuffering || (!_ready && context.watch<AppProvider>().isPlayerLoading))
              const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            if (_showControls) _controlsOverlay(playing, fullscreen),
            if (_sponsorToast)
              Positioned(
                bottom: fullscreen ? 72 : 56,
                child: AnimatedOpacity(
                  opacity: _sponsorToast ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.sbSponsor.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.skip_next, size: 16, color: Colors.black),
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
            // Sponsor markers on progress
            if (_ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _progressBar(),
              ),
            if (_toastMsg != null)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _toastMsg!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
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
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.75),
            ],
            stops: const [0, 0.25, 0.6, 1],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      fullscreen ? Icons.fullscreen_exit : Icons.arrow_back,
                      color: Colors.white,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (context.watch<AppProvider>().isSponsorBlockEnabled)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.sbSponsor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'SB',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () => _seekBy(-10),
                  icon: const Icon(Icons.replay_10),
                ),
                const SizedBox(width: 18),
                IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  onPressed: _togglePlay,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                ),
                const SizedBox(width: 18),
                IconButton(
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () => _seekBy(10),
                  icon: const Icon(Icons.forward_10),
                ),
              ],
            ),
            const Spacer(),
            // Time + feature controls (YouTube-style)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 4, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        detailsIsLive
                            ? 'LIVE'
                            : '${_fmt(_position)} / ${_fmt(_duration)}',
                        style: TextStyle(
                          color: detailsIsLive
                              ? const Color(0xFFFF5555)
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: detailsIsLive
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      _ctrlIcon(
                        _muted ? Icons.volume_off : Icons.volume_up,
                        'Mute',
                        () => _toggleMute(),
                      ),
                      _ctrlIcon(
                        _looping ? Icons.repeat_one : Icons.repeat,
                        'Loop',
                        () => _toggleLoop(),
                        active: _looping,
                      ),
                      TextButton(
                        onPressed: _showSpeedSheet,
                        child: Text(
                          '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                      if (!detailsIsLive)
                        TextButton(
                          onPressed: _showQualitySheet,
                          child: Text(
                            _quality.replaceAll(' (HLS)', ''),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                      _ctrlIcon(
                        Icons.picture_in_picture_alt_outlined,
                        'PiP',
                        () => _enterPipIfPlaying(),
                      ),
                      _ctrlIcon(
                        fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        'Fullscreen',
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
                  // Secondary actions row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipBtn(Icons.replay_10, '-10s', () => _seekBy(-10)),
                        _chipBtn(Icons.forward_10, '+10s', () => _seekBy(10)),
                        _chipBtn(
                          Icons.skip_next,
                          'Next',
                          _playNextRelated,
                        ),
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
                          Icons.closed_caption_outlined,
                          'CC',
                          () => _toast('Captions coming soon'),
                        ),
                        _chipBtn(
                          Icons.headphones,
                          'Audio',
                          _audioOnlyMode,
                        ),
                        _chipBtn(
                          Icons.settings_outlined,
                          'More',
                          _showMoreSheet,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      height: 18,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // sponsor markers
          if (_duration.inMilliseconds > 0)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: LayoutBuilder(
                  builder: (context, box) {
                    return Stack(
                      children: segments.map((s) {
                        final left =
                            (s.start * 1000 / total) * box.maxWidth;
                        final width =
                            ((s.end - s.start) * 1000 / total) * box.maxWidth;
                        return Positioned(
                          left: left.clamp(0, box.maxWidth),
                          width: width.clamp(2, box.maxWidth),
                          top: 10,
                          height: 3,
                          child: Container(color: AppTheme.sbSponsor),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppTheme.primary,
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

  Widget _infoPane(
    AppProvider provider,
    VideoDetails? video,
    Video? preview,
  ) {
    final title = video?.title ?? preview?.title ?? 'Loading…';
    final channel = video?.channelName ?? preview?.channelName ?? '';
    final views = video?.formattedViewCount ?? preview?.formattedViewCount ?? '0';
    final published = video?.publishedAt ?? preview?.publishedAt ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (video?.isLive == true || preview?.isLive == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Text('Streaming live',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        if (video?.isShort == true || preview?.isShort == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.movie_filter_outlined,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text('Shorts',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ],
            ),
          ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            if ((video?.viewCount ?? preview?.viewCount ?? 0) > 0)
              '$views views',
            if (published.isNotEmpty) published,
          ].join(' • '),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
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
                label: _dislikes != null ? _short(_dislikes!) : 'Dislike',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_dislikes != null
                          ? '$_dislikes dislikes (Return YouTube Dislike)'
                          : 'Dislike count unavailable'),
                    ),
                  );
                },
              ),
              _action(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Share.share(
                    'https://youtu.be/${widget.videoId}',
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(added
                        ? 'Saved to Watch Later'
                        : 'Removed from Watch Later'),
                  ));
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Downloading…')),
                  );
                  try {
                    await provider.downloadVideo(v);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download complete — open Downloads tab')),
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.surfaceVariant,
                child: Text(
                  channel.isNotEmpty ? channel[0].toUpperCase() : 'C',
                  style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.isEmpty ? 'Channel' : channel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Subscriptions coming soon')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Subscribe'),
              ),
            ],
          ),
        ),
        if ((video?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                video!.description,
                maxLines: _descExpanded ? 100 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // SponsorBlock card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.skip_next, color: AppTheme.sbSponsor),
            title: const Text('SponsorBlock',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              provider.sponsorSegments.isEmpty
                  ? 'Auto-skip sponsored segments'
                  : '${provider.activeSponsorSegments.length} segments loaded',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            value: provider.isSponsorBlockEnabled,
            onChanged: (_) => provider.toggleSponsorBlock(),
          ),
        ),
        if (provider.comments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Comments · ${provider.comments.length}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...provider.comments.take(8).map(_commentTile),
        ],
        if (provider.relatedVideos.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Related',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
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

  Widget _commentTile(Comment c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.surfaceVariant,
            backgroundImage: c.authorAvatar.isNotEmpty
                ? CachedNetworkImageProvider(c.authorAvatar)
                : null,
            child: c.authorAvatar.isEmpty
                ? Text(c.author.isNotEmpty ? c.author[0] : '?',
                    style: const TextStyle(fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.author} · ${c.publishedAt}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 2),
                Text(c.text,
                    style: const TextStyle(fontSize: 13, height: 1.35)),
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: active ? AppTheme.primary : AppTheme.textPrimary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? AppTheme.primary : AppTheme.textPrimary,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final speeds = [
      0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0
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
                      Text('Playback speed',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: c.textPrimary)),
                      const Spacer(),
                      Text('${_speed}x',
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700)),
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
                        title: Text('${s}x',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            )),
                        subtitle: s == 1.0
                            ? Text('Normal',
                                style: TextStyle(
                                    color: c.textMuted, fontSize: 12))
                            : null,
                        trailing: selected
                            ? const Icon(Icons.check, color: AppTheme.primary)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() => _speed = s);
                          await _controller?.setPlaybackSpeed(s);
                          if (mounted) {
                            context.read<AppProvider>().setDefaultSpeed(s);
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

  void _showQualitySheet() {
    final details = context.read<AppProvider>().currentVideo;
    if (details?.isLive == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Live streams use adaptive HLS quality automatically')),
      );
      return;
    }
    final qs = details?.availableQualities ??
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
                      Text('Quality',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: c.textPrimary)),
                      const Spacer(),
                      Text(_quality,
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700)),
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
                      String? sub;
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
                        final hasExact = d != null &&
                            (d.hlsVariants.containsKey(h) ||
                                d.progressiveByHeight.containsKey(h));
                        final hasNear = d != null &&
                            (d.hlsVariants.keys
                                    .any((x) => (x - h).abs() <= 20) ||
                                d.progressiveByHeight.keys
                                    .any((x) => (x - h).abs() <= 20));
                        if (hasExact || hasNear) {
                          final isHls = d!.hlsVariants.containsKey(h) ||
                              d.hlsVariants.keys.any((x) => (x - h).abs() <= 20);
                          sub = isHls ? 'Tap to lock · HLS' : 'Tap to lock · MP4';
                        } else if (hasHls) {
                          sub = 'via nearest HLS';
                        } else {
                          sub = 'May fallback';
                        }
                      }
                      return ListTile(
                        title: Text(q,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            )),
                        subtitle: sub == null
                            ? null
                            : Text(sub,
                                style: TextStyle(
                                    fontSize: 11, color: c.textMuted)),
                        trailing: selected
                            ? const Icon(Icons.check, color: AppTheme.primary)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() => _quality = q);
                          context.read<AppProvider>().setDefaultQuality(q);
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
                            await _startPlayback(d, quality: q);
                            final liveCtrl = _controller;
                            if (pos != null && liveCtrl != null) {
                              await liveCtrl.seekTo(pos);
                              await liveCtrl.play();
                            }
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



  Widget _ctrlIcon(IconData icon, String tip, VoidCallback onTap,
      {bool active = false}) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon,
          color: active ? AppTheme.primary : Colors.white, size: 22),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _chipBtn(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 2, bottom: 4),
      child: Material(
        color: active
            ? AppTheme.primary.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: active ? AppTheme.primary : Colors.white),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                      color: active ? AppTheme.primary : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
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
    final n = _dislikes;
    _toast(n == null
        ? 'Dislike count unavailable'
        : '${_short(n)} dislikes');
  }

  Future<void> _shareVideo() async {
    final title = context.read<AppProvider>().currentVideo?.title ??
        widget.preview?.title ??
        'VibeTube';
    await Share.share('https://youtu.be/${widget.videoId}', subject: title);
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
    await _startPlayback(d, quality: 'Audio Only');
    if (pos != null) {
      await _controller?.seekTo(pos);
      await _controller?.play();
    }
    _toast('Audio only');
  }

  void _playNextRelated() {
    final related = context.read<AppProvider>().relatedVideos;
    if (related.isEmpty) {
      _toast('No related videos');
      return;
    }
    final next = related.first;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(videoId: next.id, preview: next),
      ),
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
              title: Text('Background play',
                  style: TextStyle(color: c.textPrimary)),
              subtitle: Text(
                'Keep audio when screen is off (media notification)',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
              value: provider.isBackgroundPlayEnabled,
              onChanged: (_) async {
                provider.toggleBackgroundPlay();
                Navigator.pop(ctx);
                if (provider.isBackgroundPlayEnabled) {
                  WakelockPlus.disable();
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
              secondary:
                  Icon(Icons.picture_in_picture_alt, color: c.textPrimary),
              title:
                  Text('Auto PiP', style: TextStyle(color: c.textPrimary)),
              value: provider.isAutoPipEnabled,
              onChanged: (_) {
                provider.toggleAutoPip();
                Navigator.pop(ctx);
              },
            ),
            SwitchListTile(
              secondary: Icon(Icons.skip_next, color: c.textPrimary),
              title: Text('SponsorBlock',
                  style: TextStyle(color: c.textPrimary)),
              value: provider.isSponsorBlockEnabled,
              onChanged: (_) {
                provider.toggleSponsorBlock();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new, color: c.textPrimary),
              title: Text('Share YouTube link',
                  style: TextStyle(color: c.textPrimary)),
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
    final hs = <int>[
      ...d.hlsVariants.keys,
      ...d.progressiveByHeight.keys,
    ];
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
