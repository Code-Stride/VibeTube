import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../models/video.dart';
import 'player_screen.dart';

/// YouTube-style vertical swipeable Shorts feed.
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
                  const Icon(Icons.movie_filter_outlined,
                      size: 56, color: Colors.white38),
                  const SizedBox(height: 12),
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
            itemCount: provider.shortsVideos.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              // Load more if near the end
              if (i >= provider.shortsVideos.length - 3) {
                provider.loadMoreShorts();
              }
            },
            itemBuilder: (context, index) {
              final short = provider.shortsVideos[index];
              return _ShortCard(
                video: short,
                isActive: index == _currentIndex,
              );
            },
          );
        },
      ),
    );
  }
}

class _ShortCard extends StatelessWidget {
  final Video video;
  final bool isActive;

  const _ShortCard({required this.video, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(videoId: video.id, preview: video),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail as background
          if (video.thumbnailUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: video.thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.black),
              errorWidget: (_, __, ___) => Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
                ),
              ),
            )
          else
            Container(color: Colors.black),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0, 0.2, 0.5, 1],
              ),
            ),
          ),

          // Play icon center
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white70,
              size: 64,
            ),
          ),

          // Bottom info
          Positioned(
            left: 16,
            right: 72,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                const SizedBox(height: 6),
                if (video.channelName.isNotEmpty)
                  Text(
                    video.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (video.viewCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${video.formattedViewCount} views',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Right side action buttons
          Positioned(
            right: 12,
            bottom: 80,
            child: Column(
              children: [
                _actionBtn(Icons.thumb_up_outlined, 'Like'),
                const SizedBox(height: 20),
                _actionBtn(Icons.thumb_down_outlined, 'Dislike'),
                const SizedBox(height: 20),
                _actionBtn(Icons.comment_outlined, 'Comments'),
                const SizedBox(height: 20),
                _actionBtn(Icons.share_outlined, 'Share'),
                const SizedBox(height: 20),
                _actionBtn(Icons.more_vert, 'More'),
              ],
            ),
          ),

          // Shorts badge top
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_filter, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Shorts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
