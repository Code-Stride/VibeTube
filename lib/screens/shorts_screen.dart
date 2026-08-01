import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_provider.dart';
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
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (provider.shortsVideos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline, size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Text('No Shorts available', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => provider.loadShorts(), child: const Text('Retry')),
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
              if (i >= provider.shortsVideos.length - 3) provider.loadMoreShorts();
            },
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

class _ShortPlayerState extends State<_ShortPlayer> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _showPlayPause = false;
  bool _liked = false;
  bool _disliked = false;
  bool _showHeart = false;
  Offset? _heartPosition;
  Timer? _hideTimer;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _heartScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.elasticOut),
    );
    _initPlayer();
  }

  @override
  void didUpdateWidget(_ShortPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller?.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  Future<void> _initPlayer() async {
    try {
      final provider = context.read<AppProvider>();
      final details = await provider.client.getVideoDetails(widget.video.id);
      if (!mounted) return;

      String? playUrl;
      if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
        playUrl = details.hlsUrl;
      } else if (details.hlsVariants.isNotEmpty) {
        final sorted = details.hlsVariants.keys.toList()..sort();
        playUrl = details.hlsVariants[sorted.first];
      } else if (details.bestMuxedUrl != null) {
        playUrl = details.bestMuxedUrl;
      } else if (details.preferredPlayUrl != null) {
        playUrl = details.preferredPlayUrl;
      }

      if (playUrl == null || playUrl.isEmpty || !mounted) return;

      final isHls = playUrl.contains('m3u8');
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: isHls
            ? {'User-Agent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)', 'Accept': '*/*'}
            : {'User-Agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip', 'Referer': 'https://www.youtube.com/'},
      );
      await _controller!.initialize().timeout(const Duration(seconds: 25));
      if (!mounted) { _controller?.dispose(); return; }
      await _controller!.setLooping(true);
      if (widget.isActive) await _controller!.play();
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('Short player init failed: $e');
    }
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      _showPlayPause = true;
      c.value.isPlaying ? c.pause() : c.play();
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showPlayPause = false);
    });
  }

  void _doubleTapLike(TapDownDetails details) {
    setState(() {
      _liked = true;
      _showHeart = true;
      _heartPosition = details.localPosition;
    });
    _heartAnimController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
    context.read<AppProvider>().toggleLike(widget.video);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _heartAnimController.dispose();
    _controller?.dispose();
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
                aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 9 / 16,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                if (widget.video.thumbnailUrl.isNotEmpty)
                  CachedNetworkImage(imageUrl: widget.video.thumbnailUrl, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black),
                    errorWidget: (_, __, ___) => Container(color: Colors.black, child: const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 48))),
                  )
                else
                  Container(color: Colors.black),
                Container(color: Colors.black45),
                if (!_ready) const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              ],
            ),

          // YouTube-exact gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black45, Colors.transparent, Colors.transparent, Colors.black87],
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
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: Icon(
                  _controller?.value.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 36,
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
            left: 12, right: 60, bottom: 16,
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
                        widget.video.channelName.isNotEmpty ? widget.video.channelName[0].toUpperCase() : 'V',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.video.channelName.isEmpty ? 'VibeTube' : widget.video.channelName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Subscribe', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Title
                Text(
                  widget.video.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
                ),
                if (widget.video.viewCount > 0) ...[
                  const SizedBox(height: 4),
                  Text('${widget.video.formattedViewCount} views',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ],
            ),
          ),

          // Right side action buttons (YouTube-exact)
          Positioned(
            right: 8, bottom: 80,
            child: Column(
              children: [
                _actionBtn(_liked ? Icons.favorite : Icons.favorite_border, 'Like',
                  onTap: () { context.read<AppProvider>().toggleLike(widget.video); setState(() => _liked = !_liked); },
                  color: _liked ? Colors.red : Colors.white),
                const SizedBox(height: 20),
                _actionBtn(Icons.thumb_down_outlined, 'Dislike',
                  onTap: () => setState(() => _disliked = !_disliked),
                  color: _disliked ? Colors.blue : Colors.white),
                const SizedBox(height: 20),
                _actionBtn(Icons.comment_outlined, 'Comments',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PlayerScreen(videoId: widget.video.id, preview: widget.video)))),
                const SizedBox(height: 20),
                _actionBtn(Icons.share_outlined, 'Share',
                  onTap: () => Share.share(ShareLinks.shareText(widget.video.id, widget.video.title), subject: widget.video.title)),
                const SizedBox(height: 20),
                _actionBtn(Icons.more_vert, 'More', onTap: () => _showMoreSheet()),
              ],
            ),
          ),

          // Progress bar at bottom
          if (_ready && _controller != null && _controller!.value.isInitialized && _controller!.value.duration.inMilliseconds > 0)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: VideoProgressIndicator(
                _controller!, allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white30, backgroundColor: Colors.white12),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, {VoidCallback? onTap, Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showMoreSheet() {
    final c = VibeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(leading: Icon(Icons.watch_later_outlined, color: c.textPrimary), title: Text('Save to Watch Later', style: TextStyle(color: c.textPrimary)),
              onTap: () { Navigator.pop(ctx); context.read<AppProvider>().toggleWatchLater(widget.video); }),
            ListTile(leading: Icon(Icons.playlist_add, color: c.textPrimary), title: Text('Save to playlist', style: TextStyle(color: c.textPrimary)),
              onTap: () => Navigator.pop(ctx)),
            ListTile(leading: Icon(Icons.flag_outlined, color: c.textPrimary), title: Text('Report', style: TextStyle(color: c.textPrimary)),
              onTap: () => Navigator.pop(ctx)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
