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

class PlayerScreen extends StatefulWidget {
  final String videoId;
  final Video? preview;
  final String? localPath;

  const PlayerScreen({
    super.key,
    required this.videoId,
    this.preview,
    this.localPath,
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _boot();
  }

  Future<void> _boot() async {
    final provider = context.read<AppProvider>();
    _speed = provider.defaultSpeed;
    _quality = provider.defaultQuality.isEmpty ? 'Auto (HLS)' : provider.defaultQuality;
    if (_quality == 'Auto') _quality = 'Auto (HLS)';
    _liked = await provider.isLiked(widget.videoId);
    _pipSupported = await NativePlayer.isPipSupported();
    await NativePlayer.setAutoPip(provider.isAutoPipEnabled);
    NativePlayer.listenPip((inPip) {
      if (!mounted) return;
      setState(() => _inPip = inPip);
    });

    // Offline local file
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      try {
        await _attachController(widget.localPath!);
        // still refresh metadata in background
        provider.loadVideoDetails(widget.videoId, preview: widget.preview);
        return;
      } catch (e) {
        debugPrint('local play failed: $e');
      }
    }

    // Start loading stream immediately
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
    final q = quality ?? _quality;

    // Build ordered candidate URLs: chosen quality → all muxed → HLS
    final candidates = <String>[];
    void add(String? u) {
      if (u != null && u.isNotEmpty && !candidates.contains(u)) {
        candidates.add(u);
      }
    }

    // Quality-aware order
    add(details.urlForQuality(q));
    if (q.startsWith('Auto') || q == 'Best') {
      add(details.hlsUrl); // high quality adaptive first
      add(details.preferredPlayUrl);
      add(details.bestMuxedUrl);
    } else {
      add(details.bestMuxedUrl);
      add(details.hlsUrl);
    }
    final muxed = details.formats.where((f) => f.isMuxed && f.url.isNotEmpty).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    for (final f in muxed) {
      add(f.url);
    }
    for (final f in details.formats) {
      if (!f.isAudioOnly && f.url.isNotEmpty) add(f.url);
    }
    add(details.hlsUrl);

    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _isBuffering = false;
          _ready = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable stream URL found for this video')),
        );
      }
      return;
    }

    Object? lastErr;
    for (final url in candidates) {
      try {
        await _attachController(url);
        if (_ready) return;
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
        SnackBar(content: Text('Playback failed: $lastErr')),
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
    await prev?.dispose();

    final isLocal = url.startsWith('/') || url.startsWith('file:');
    late final VideoPlayerController c;
    if (isLocal) {
      final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
      c = VideoPlayerController.file(File(path));
    } else {
      // Try with YT-like headers first
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: const {
          'User-Agent':
              'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
          'Referer': 'https://www.youtube.com/',
          'Origin': 'https://www.youtube.com',
        },
      );
    }

    try {
      await c.initialize().timeout(const Duration(seconds: 20));
    } catch (e) {
      await c.dispose();
      // Retry network without custom headers (some CDNs reject them)
      if (!isLocal) {
        final c2 = VideoPlayerController.networkUrl(Uri.parse(url));
        try {
          await c2.initialize().timeout(const Duration(seconds: 20));
          await _finishAttach(c2, url);
          return;
        } catch (e2) {
          await c2.dispose();
          rethrow;
        }
      }
      rethrow;
    }
    await _finishAttach(c, url);
  }

  Future<void> _finishAttach(VideoPlayerController c, String url) async {
    if (!mounted) {
      await c.dispose();
      return;
    }
    await c.setLooping(false);
    await c.setPlaybackSpeed(_speed);
    c.addListener(_onTick);
    setState(() {
      _controller = c;
      _ready = true;
      _isBuffering = false;
      _activeUrl = url;
      _duration = c.value.duration;
    });
    await c.play();
    final provider = context.read<AppProvider>();
    if (provider.isBackgroundPlayEnabled) {
      WakelockPlus.enable();
      final title = provider.currentVideo?.title ?? widget.preview?.title ?? 'VibeTube';
      final artist = provider.currentVideo?.channelName ?? widget.preview?.channelName ?? 'Playing';
      await NativePlayer.startBackground(title: title, artist: artist);
      _bgActive = true;
    }
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
    // SponsorBlock auto-skip
    _maybeSkipSponsor(v.position);
  }

  void _startPosTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final c = _controller;
      if (c == null || !c.value.isInitialized || _seeking) return;
      if (!mounted) return;
      setState(() {
        _position = c.value.position;
        _duration = c.value.duration;
      });
    });
  }

  void _maybeSkipSponsor(Duration pos) {
    final provider = context.read<AppProvider>();
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
    if (c.value.isPlaying) {
      await c.pause();
      WakelockPlus.disable();
    } else {
      await c.play();
      WakelockPlus.enable();
    }
    setState(() {});
    _armHide();
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    WakelockPlus.disable();
    if (_bgActive) {
      NativePlayer.stopBackground();
      _bgActive = false;
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

    return Scaffold(
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
    final aspect = (c != null && c.value.isInitialized && c.value.aspectRatio > 0)
        ? c.value.aspectRatio
        : 16 / 9;

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
                    onPressed: () {
                      if (fullscreen) {
                        _exitFullscreen();
                      } else {
                        Navigator.pop(context);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
              child: Row(
                children: [
                  Text(
                    '${_fmt(_position)} / ${_fmt(_duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _showSpeedSheet,
                    child: Text(
                      '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _showQualitySheet,
                    child: Text(
                      _quality,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _inPip ? Icons.picture_in_picture_alt : Icons.picture_in_picture_alt_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: 'Picture-in-Picture',
                    onPressed: () async {
                      final ok = await NativePlayer.enterPip();
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_pipSupported
                                ? 'PiP unavailable right now — try while playing'
                                : 'PiP not supported on this device'),
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (fullscreen) {
                        _exitFullscreen();
                      } else {
                        _enterFullscreen();
                      }
                    },
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
                    hasHls
                        ? 'HLS adaptive unlocked — up to 1080p/4K when available'
                        : 'Only progressive streams found (often max 360p)',
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
                      if (q.startsWith('Auto')) {
                        sub = hasHls ? 'Best available via HLS' : 'Best progressive';
                      } else if (q == 'Audio Only') {
                        sub = 'Music / background friendly';
                      } else if (hasHls && q != '360p') {
                        sub = 'HLS adaptive';
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
                            await _startPlayback(d, quality: q);
                            if (pos != null) {
                              await _controller?.seekTo(pos);
                              await _controller?.play();
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
