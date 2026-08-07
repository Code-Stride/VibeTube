import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_provider.dart';
import '../providers/mini_player_controller.dart';
import '../services/audio_helper.dart';
import '../utils/theme.dart';
import '../utils/share_links.dart';
import '../models/video.dart';
import 'player_screen.dart';

/// YouTube-exact Shorts feed with inline video playback.
class ShortsScreen extends StatefulWidget {
  final bool isActive;
  const ShortsScreen({super.key, this.isActive = true});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppProvider>();
      if (provider.shortsVideos.isEmpty) provider.loadShorts();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isShortsLoading && provider.shortsVideos.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (provider.shortsVideos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    size: 64,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Shorts available',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadShorts(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const PageScrollPhysics(),
            itemCount: provider.shortsVideos.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              if (i >= provider.shortsVideos.length - 3) {
                provider.loadMoreShorts();
              }
            },
            // Keep neighbours alive so swiping back does not re-fetch.
            allowImplicitScrolling: false,
            itemBuilder: (context, index) {
              return _ShortPlayer(
                video: provider.shortsVideos[index],
                isActive: widget.isActive && index == _currentIndex,
              );
            },
          );
        },
      ),
    );
  }
}

class _ShortPlayer extends StatefulWidget {
  final Video video;
  final bool isActive;
  const _ShortPlayer({required this.video, required this.isActive});

  @override
  State<_ShortPlayer> createState() => _ShortPlayerState();
}

class _ShortPlayerState extends State<_ShortPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _showPlayPause = false;
  bool _liked = false;
  bool _disliked = false;
  bool _showHeart = false;
  String? _playerError;
  int _playerRequestId = 0;
  Offset? _heartPosition;
  Timer? _hideTimer;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.elasticOut),
    );
    // Shorts previously ignored the audio session entirely: pulling out
    // headphones kept playing on the loudspeaker and an incoming call talked
    // over the video.
    AudioHelper.addListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
    );
    // Reflect the real stored state instead of always showing "unliked".
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final liked = await context.read<AppProvider>().isLiked(widget.video.id);
      if (mounted && liked != _liked) setState(() => _liked = liked);
    });
    _initPlayer();
  }

  @override
  void didUpdateWidget(_ShortPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _resumeWithFocus();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  /// Taking audio focus stops the mini player (or any other app) from playing
  /// underneath us — previously a Short and the mini player produced sound at
  /// the same time.
  Future<void> _resumeWithFocus() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    context.read<MiniPlayerController>().pauseIfPlaying();
    await AudioHelper.requestFocus();
    if (!mounted || !widget.isActive) return;
    await c.play();
  }

  Future<void> _initPlayer() async {
    final requestId = ++_playerRequestId;
    // Retry used to overwrite _controller without disposing the old one. On
    // Android there are only a handful of hardware decoders, so a few retries
    // left every Short rendering black.
    final previous = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _playerError = null;
        _ready = false;
      });
    }
    try {
      await previous?.dispose();
    } catch (_) {}

    try {
      final provider = context.read<AppProvider>();
      final details = await provider.client.getVideoDetails(widget.video.id);
      if (!mounted || requestId != _playerRequestId) return;

      String? playUrl;
      if (details.hlsVariants.isNotEmpty) {
        final heights = details.hlsVariants.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        final preferred = heights.firstWhere(
          (h) => h <= 720,
          orElse: () => heights.last,
        );
        playUrl = details.hlsVariants[preferred];
      } else if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
        playUrl = details.hlsUrl;
      } else if (details.preferredPlayUrl != null) {
        playUrl = details.preferredPlayUrl;
      } else if (details.bestMuxedUrl != null) {
        playUrl = details.bestMuxedUrl;
      }

      // Bailing out silently here left _ready false forever, so the Short sat
      // on a spinner with no message and no way to retry.
      if (playUrl == null || playUrl.isEmpty) {
        if (mounted && requestId == _playerRequestId) {
          setState(() => _playerError = 'No playable stream for this Short');
        }
        return;
      }
      if (!mounted || requestId != _playerRequestId) return;

      final isHls = playUrl.contains('m3u8');
      final candidate = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: isHls
            ? {
                'User-Agent':
                    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
                'Accept': '*/*',
              }
            : {
                'User-Agent':
                    'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
                'Referer': 'https://www.youtube.com/',
              },
      );
      try {
        await candidate.initialize().timeout(const Duration(seconds: 25));
      } catch (_) {
        await candidate.dispose();
        rethrow;
      }
      if (!mounted || requestId != _playerRequestId) {
        await candidate.dispose();
        return;
      }
      _controller = candidate;
      await candidate.setLooping(true);
      candidate.addListener(_onControllerTick);
      if (!mounted || requestId != _playerRequestId) return;
      setState(() => _ready = true);
      if (widget.isActive) await _resumeWithFocus();
    } catch (e) {
      debugPrint('Short player init failed: $e');
      if (mounted && requestId == _playerRequestId) {
        setState(() => _playerError = 'Unable to play this Short');
      }
    }
  }

  bool _pausedByInterruption = false;

  void _onBecomingNoisy() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    _pausedByInterruption = false;
    c.pause();
    if (mounted) setState(() {});
  }

  void _onShouldPause(bool permanent) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    _pausedByInterruption = !permanent;
    c.pause();
    if (mounted) setState(() {});
  }

  void _onMayResume() {
    if (!_pausedByInterruption || !widget.isActive) return;
    _pausedByInterruption = false;
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isPlaying) return;
    _resumeWithFocus();
  }

  void _onDuck(bool ducking) {
    _controller?.setVolume(ducking ? AudioHelper.duckVolume : 1.0);
  }

  /// Surfaces decoder/network failures instead of freezing on a black frame.
  void _onControllerTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (c.value.hasError && _playerError == null) {
      setState(() => _playerError = 'Playback error — tap retry');
    }
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // Do the async work outside setState, then rebuild once it has actually
    // taken effect — otherwise the icon rendered the pre-toggle state.
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await _resumeWithFocus();
    }
    if (!mounted) return;
    setState(() => _showPlayPause = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showPlayPause = false);
    });
  }

  /// Double-tap is a "like", never a toggle. Double-tapping an already-liked
  /// Short used to silently remove it from Liked while showing a red heart.
  void _doubleTapLike(TapDownDetails details) {
    setState(() {
      _showHeart = true;
      _heartPosition = details.localPosition;
    });
    _heartAnimController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
    if (_liked) return;
    setState(() => _liked = true);
    context.read<AppProvider>().toggleLike(widget.video);
  }

  @override
  void dispose() {
    _playerRequestId++;
    AudioHelper.removeListeners(
      onBecomingNoisy: _onBecomingNoisy,
      onShouldPause: _onShouldPause,
      onMayResume: _onMayResume,
      onDuck: _onDuck,
    );
    _hideTimer?.cancel();
    _heartAnimController.dispose();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onControllerTick);
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTapDown: _doubleTapLike,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video surface
          if (_ready && _controller != null && _controller!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio > 0
                    ? _controller!.value.aspectRatio
                    : 9 / 16,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                if (widget.video.thumbnailUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.video.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 48,
                        ),
                      ),
                    ),
                  )
                else
                  Container(color: Colors.black),
                Container(color: Colors.black45),
                if (_playerError != null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 42,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _playerError!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        TextButton(
                          onPressed: _initPlayer,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else if (!_ready)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),

          // YouTube-exact gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black45,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black87,
                ],
                stops: [0, 0.1, 0.5, 1],
              ),
            ),
          ),

          // Play/Pause indicator
          AnimatedOpacity(
            opacity: _showPlayPause ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _controller?.value.isPlaying == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),

          // Double-tap heart animation
          if (_showHeart && _heartPosition != null)
            Positioned(
              left: _heartPosition!.dx - 40,
              top: _heartPosition!.dy - 40,
              child: ScaleTransition(
                scale: _heartScale,
                child: const Icon(Icons.favorite, color: Colors.red, size: 80),
              ),
            ),

          // Bottom info (YouTube-exact layout)
          Positioned(
            left: 12,
            right: 60,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Channel row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey,
                      child: Text(
                        widget.video.channelName.isNotEmpty
                            ? widget.video.channelName[0].toUpperCase()
                            : 'V',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.video.channelName.isEmpty
                            ? 'VibeTube'
                            : widget.video.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Consumer<AppProvider>(
                      builder: (context, p, _) {
                        final id = widget.video.channelId;
                        final subbed = p.isSubscribed(id);
                        return GestureDetector(
                          onTap: id.isEmpty
                              ? null
                              : () => p.toggleSubscription(id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: subbed ? Colors.white24 : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              subbed ? 'Subscribed' : 'Subscribe',
                              style: TextStyle(
                                color: subbed ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Title
                Text(
                  widget.video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                if (widget.video.viewCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${widget.video.formattedViewCount} views',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),

          // Right side action buttons (YouTube-exact)
          Positioned(
            right: 8,
            bottom: 80,
            child: Column(
              children: [
                _actionBtn(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  'Like',
                  onTap: () async {
                    final now = await context
                        .read<AppProvider>()
                        .toggleLike(widget.video);
                    if (mounted) setState(() => _liked = now);
                  },
                  color: _liked ? Colors.red : Colors.white,
                ),
                const SizedBox(height: 20),
                _actionBtn(
                  Icons.thumb_down_outlined,
                  'Dislike',
                  onTap: () => setState(() => _disliked = !_disliked),
                  color: _disliked ? Colors.blue : Colors.white,
                ),
                const SizedBox(height: 20),
                _actionBtn(
                  Icons.comment_outlined,
                  'Comments',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        videoId: widget.video.id,
                        preview: widget.video,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _actionBtn(
                  Icons.share_outlined,
                  'Share',
                  onTap: () => Share.share(
                    ShareLinks.shareText(widget.video.id, widget.video.title),
                    subject: widget.video.title,
                  ),
                ),
                const SizedBox(height: 20),
                _actionBtn(
                  Icons.more_vert,
                  'More',
                  onTap: () => _showMoreSheet(),
                ),
              ],
            ),
          ),

          // Progress bar at bottom
          if (_ready &&
              _controller != null &&
              _controller!.value.isInitialized &&
              _controller!.value.duration.inMilliseconds > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreSheet() {
    final c = VibeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.surfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.watch_later_outlined, color: c.textPrimary),
              title: Text(
                'Save to Watch Later',
                style: TextStyle(color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.read<AppProvider>().toggleWatchLater(widget.video);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add, color: c.textPrimary),
              title: Text(
                'Save to playlist',
                style: TextStyle(color: c.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: c.textPrimary),
              title: Text('Report', style: TextStyle(color: c.textPrimary)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
