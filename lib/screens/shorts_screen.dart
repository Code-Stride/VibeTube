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
import '../services/piped_service.dart';
import 'player_screen.dart';

/// YouTube-style vertical swipeable Shorts with inline video playback.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

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
      if (provider.shortsVideos.isEmpty) {
        provider.loadShorts();
      }
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
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }
          if (provider.shortsVideos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie_filter_outlined, size: 56, color: Colors.white38),
                  const SizedBox(height: 12),
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
            itemCount: provider.shortsVideos.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              if (i >= provider.shortsVideos.length - 3) provider.loadMoreShorts();
            },
            itemBuilder: (context, index) {
              return _ShortPlayer(
                video: provider.shortsVideos[index],
                isActive: index == _currentIndex,
              );
            },
          );
        },
      ),
    );
  }
}

/// Individual short — plays video inline like YouTube Shorts.
class _ShortPlayer extends StatefulWidget {
  final Video video;
  final bool isActive;
  const _ShortPlayer({required this.video, required this.isActive});

  @override
  State<_ShortPlayer> createState() => _ShortPlayerState();
}

class _ShortPlayerState extends State<_ShortPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _showPlayPause = false;
  bool _liked = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
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
      // Use Piped API for reliable direct URLs
      final piped = await PipedService.getStreams(widget.video.id);
      if (!mounted || piped == null || piped.bestStreamUrl == null) return;

      final url = piped.bestStreamUrl!;
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Accept': '*/*',
        },
      );
      await _controller!.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        _controller?.dispose();
        return;
      }
      await _controller!.setLooping(true);
      if (widget.isActive) {
        await _controller!.play();
      }
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
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showPlayPause = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
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
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.black, child: const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 48))),
                  )
                else
                  Container(color: Colors.black),
                Container(color: Colors.black45),
                if (!_ready)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
              ],
            ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0, 0.15, 0.5, 1],
              ),
            ),
          ),

          // Play/Pause indicator
          if (_showPlayPause)
            Center(
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: Icon(
                  _controller?.value.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 40,
                ),
              ),
            ),

          // Bottom info
          Positioned(
            left: 16, right: 72, bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                      child: Text(
                        widget.video.channelName.isNotEmpty ? widget.video.channelName[0].toUpperCase() : 'V',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.video.channelName.isEmpty ? 'VibeTube' : widget.video.channelName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Subscribe', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.video.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
                ),
                if (widget.video.viewCount > 0) ...[
                  const SizedBox(height: 4),
                  Text('${widget.video.formattedViewCount} views', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ],
            ),
          ),

          // Right side action buttons
          Positioned(
            right: 12, bottom: 80,
            child: Column(
              children: [
                _actionBtn(_liked ? Icons.thumb_up : Icons.thumb_up_outlined, 'Like',
                  onTap: () { context.read<AppProvider>().toggleLike(widget.video); setState(() => _liked = !_liked); },
                  active: _liked),
                const SizedBox(height: 16),
                _actionBtn(Icons.thumb_down_outlined, 'Dislike', onTap: () {}),
                const SizedBox(height: 16),
                _actionBtn(Icons.comment_outlined, 'Comments',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(videoId: widget.video.id, preview: widget.video)))),
                const SizedBox(height: 16),
                _actionBtn(Icons.share_outlined, 'Share',
                  onTap: () => Share.share(ShareLinks.shareText(widget.video.id, widget.video.title), subject: widget.video.title)),
                const SizedBox(height: 16),
                _actionBtn(Icons.more_vert, 'More', onTap: () => _showMoreSheet()),
              ],
            ),
          ),

          // Shorts badge
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_filter, size: 18, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Shorts', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),

          // Progress bar
          if (_ready && _controller != null && _controller!.value.isInitialized && _controller!.value.duration.inMilliseconds > 0)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: VideoProgressIndicator(
                _controller!, allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: AppTheme.primary, bufferedColor: Colors.white24, backgroundColor: Colors.white12),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, {VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: active ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: active ? AppTheme.primary : Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: active ? AppTheme.primary : Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showMoreSheet() {
    final c = VibeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.watch_later_outlined, color: c.textPrimary),
              title: Text('Save to Watch Later', style: TextStyle(color: c.textPrimary)),
              onTap: () { Navigator.pop(ctx); context.read<AppProvider>().toggleWatchLater(widget.video); },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new, color: c.textPrimary),
              title: Text('Open full player', style: TextStyle(color: c.textPrimary)),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(videoId: widget.video.id, preview: widget.video))); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
