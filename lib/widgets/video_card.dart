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
    final c = VibeColors.of(context);
    if (compact) return _compact(context, c);
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
                  _thumb(video.thumbnailUrl, c.surfaceLight),
                  if (video.isLive)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _liveBadge(),
                    )
                  else if (video.isShort)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _shortBadge(),
                    ),
                  if (!video.isLive && video.formattedDuration.isNotEmpty)
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
                  _avatar(video, c),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: c.textPrimary,
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
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.more_vert, size: 20, color: c.textSecondary),
                    onPressed: () => _options(context, c),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, VibeColors c) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
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
                    _thumb(video.thumbnailUrl, c.surfaceLight),
                    if (video.isLive)
                      Positioned(left: 6, top: 6, child: _liveBadge())
                    else if (video.isShort)
                      Positioned(left: 6, top: 6, child: _shortBadge()),
                    if (!video.isLive && video.formattedDuration.isNotEmpty)
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
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  Text(
                    [
                      if (video.viewCount > 0)
                        '${video.formattedViewCount} views',
                      if (video.publishedAt.isNotEmpty) video.publishedAt,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url, Color bg) {
    if (url.isEmpty) {
      return Container(
        color: bg,
        child: Icon(Icons.play_circle_outline, color: bg.computeLuminance() > 0.5 ? Colors.black38 : Colors.white38, size: 42),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: bg),
      errorWidget: (_, __, ___) => Container(
        color: bg,
        child: const Icon(Icons.broken_image, color: Colors.grey),
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

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _shortBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vertical_align_center, size: 12, color: Colors.white),
          SizedBox(width: 2),
          Text(
            'SHORTS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Video v, VibeColors c) {
    final letter =
        v.channelName.isNotEmpty ? v.channelName[0].toUpperCase() : 'V';
    if (v.channelAvatar.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: CachedNetworkImageProvider(v.channelAvatar),
        backgroundColor: c.surfaceLight,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: c.surfaceVariant,
      child: Text(letter,
          style: const TextStyle(
              color: AppTheme.primary, fontWeight: FontWeight.bold)),
    );
  }

  void _options(BuildContext outerContext, VibeColors c) {
    final provider = outerContext.read<AppProvider>();
    final rootNav = Navigator.of(outerContext, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(outerContext);
    showModalBottomSheet(
      context: outerContext,
      backgroundColor: c.surface,
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
                  color: c.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.watch_later_outlined, color: c.textPrimary),
                title: Text('Save to Watch Later',
                    style: TextStyle(color: c.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final added = await provider.toggleWatchLater(video);
                  messenger.showSnackBar(SnackBar(
                    content: Text(added
                        ? 'Saved to Watch Later'
                        : 'Removed from Watch Later'),
                  ));
                },
              ),
              ListTile(
                leading: Icon(Icons.thumb_up_outlined, color: c.textPrimary),
                title: Text('Like', style: TextStyle(color: c.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final liked = await provider.toggleLike(video);
                  messenger.showSnackBar(SnackBar(
                    content: Text(liked ? 'Added to Liked' : 'Removed like'),
                  ));
                },
              ),
              ListTile(
                leading: Icon(Icons.download_outlined, color: c.textPrimary),
                title: Text('Download', style: TextStyle(color: c.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Starting download…')),
                  );
                  try {
                    await provider.downloadVideo(video);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Download complete')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Download failed: $e')),
                    );
                  }
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
