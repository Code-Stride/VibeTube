import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';

class VideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  final bool compact;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _compact(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(video.thumbnailUrl, borderRadius: 0),
                  if (video.formattedDuration.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _badge(video.formattedDuration),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(video),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (video.channelName.isNotEmpty) video.channelName,
                            if (video.viewCount > 0)
                              '${video.formattedViewCount} views',
                            if (video.publishedAt.isNotEmpty) video.publishedAt,
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_vert,
                        size: 20, color: AppTheme.textSecondary),
                    onPressed: () => _options(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 168,
                height: 94,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _thumb(video.thumbnailUrl, borderRadius: 10),
                    if (video.formattedDuration.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _badge(video.formattedDuration),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    [
                      if (video.viewCount > 0)
                        '${video.formattedViewCount} views',
                      if (video.publishedAt.isNotEmpty) video.publishedAt,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url, {double borderRadius = 0}) {
    if (url.isEmpty) {
      return Container(
        color: AppTheme.surfaceLight,
        child: const Center(
          child: Icon(Icons.play_circle_outline,
              color: AppTheme.textMuted, size: 42),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppTheme.surfaceLight),
      errorWidget: (_, __, ___) => Container(
        color: AppTheme.surfaceLight,
        child: const Icon(Icons.broken_image, color: AppTheme.textMuted),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _avatar(Video v) {
    final letter =
        v.channelName.isNotEmpty ? v.channelName[0].toUpperCase() : 'V';
    if (v.channelAvatar.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: CachedNetworkImageProvider(v.channelAvatar),
        backgroundColor: AppTheme.surfaceLight,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.surfaceVariant,
      child: Text(letter,
          style: const TextStyle(
              color: AppTheme.primary, fontWeight: FontWeight.bold)),
    );
  }

  void _options(BuildContext context) {
    final provider = context.read<AppProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.watch_later_outlined),
                title: const Text('Save to Watch Later'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final added = await provider.toggleWatchLater(video);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(added
                          ? 'Saved to Watch Later'
                          : 'Removed from Watch Later'),
                    ));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.thumb_up_outlined),
                title: const Text('Like'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final liked = await provider.toggleLike(video);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(liked ? 'Added to Liked' : 'Removed like'),
                    ));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download'),
                onTap: () async {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Starting download…')),
                  );
                  try {
                    await provider.downloadVideo(video);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download complete')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Download failed: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(ctx);
                  // handled by share_plus in player
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
