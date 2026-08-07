import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video.dart';
import '../providers/app_provider.dart';
import '../utils/text_utils.dart';
import '../utils/theme.dart';

/// YouTube-exact video card — matches YouTube's layout pixel-for-pixel.
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
    if (compact) return _compactCard(context);
    return _fullCard(context);
  }

  /// YouTube full card (home feed): thumbnail → title → channel row
  Widget _fullCard(BuildContext context) {
    final c = VibeColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with duration badge
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(video.thumbnailUrl, c.surfaceLight),
                  if (video.isLive) Positioned(left: 8, bottom: 8, child: _liveBadge()),
                  if (!video.isLive && video.formattedDuration.isNotEmpty)
                    Positioned(right: 8, bottom: 8, child: _durationBadge(video.formattedDuration)),
                  if (video.isShort) Positioned(left: 8, top: 8, child: _shortBadge()),
                ],
              ),
            ),
            // Info row: avatar + title/channel/views
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel avatar
                  _avatar(video, c),
                  const SizedBox(width: 12),
                  // Title + metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Channel name
                        Text(
                          video.channelName.isEmpty ? 'VibeTube' : video.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.textSecondary),
                        ),
                        // Views + time
                        if (video.viewCount > 0 || video.publishedAt.isNotEmpty)
                          Text(
                            [
                              if (video.viewCount > 0) '${video.formattedViewCount} views',
                              if (video.publishedAt.isNotEmpty) video.publishedAt,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: c.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  // More button
                  IconButton(
                    icon: Icon(Icons.more_vert, size: 20, color: c.textSecondary),
                    onPressed: () => _showOptions(context, c),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// YouTube compact card (search/related): horizontal layout
  Widget _compactCard(BuildContext context) {
    final c = VibeColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: SizedBox(
                  width: 168,
                  height: 94,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _thumb(video.thumbnailUrl, c.surfaceLight),
                      if (video.isLive) Positioned(left: 6, bottom: 6, child: _liveBadge()),
                      if (!video.isLive && video.formattedDuration.isNotEmpty)
                        Positioned(right: 6, bottom: 6, child: _durationBadge(video.formattedDuration)),
                      if (video.isShort) Positioned(left: 6, top: 6, child: _shortBadge()),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        video.channelName.isEmpty ? 'VibeTube' : video.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      Text(
                        [
                          if (video.viewCount > 0) '${video.formattedViewCount} views',
                          if (video.publishedAt.isNotEmpty) video.publishedAt,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              // More button
              IconButton(
                icon: Icon(Icons.more_vert, size: 20, color: c.textSecondary),
                onPressed: () => _showOptions(context, c),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String url, Color bg) {
    if (url.isEmpty) {
      return Container(
        color: bg,
        child: Center(child: Icon(Icons.play_circle_outline, color: bg.computeLuminance() > 0.5 ? Colors.black38 : Colors.white38, size: 42)),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: bg),
      errorWidget: (_, __, ___) => Container(color: bg, child: const Icon(Icons.broken_image, color: Colors.grey)),
    );
  }

  Widget _durationBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFFF0000), borderRadius: BorderRadius.circular(2)),
      child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }

  Widget _shortBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_filter, size: 12, color: Colors.white),
          SizedBox(width: 2),
          Text('Shorts', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _avatar(Video v, VibeColors c) {
    if (v.channelAvatar.isNotEmpty) {
      // CachedNetworkImageProvider has no widget-level errorWidget, so a 404
      // or decode failure used to render an empty/error circle (and can throw
      // during image resolution). Resolve the provider first and fall back to
      // the initials avatar if it errors, so a bad avatar URL never leaves a
      // broken image in the card.
      return _NetworkAvatar(
        url: v.channelAvatar,
        radius: 18,
        backgroundColor: c.surfaceLight,
        fallback: initialLetter(v.channelName),
        fallbackBg: c.surfaceVariant,
        fallbackFg: c.textPrimary,
      );
    }
    final letter = initialLetter(v.channelName);
    return CircleAvatar(
      radius: 18,
      backgroundColor: c.surfaceVariant,
      child: Text(letter, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  void _showOptions(BuildContext outerContext, VibeColors c) {
    final provider = outerContext.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(outerContext);
    showModalBottomSheet(
      context: outerContext,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.watch_later_outlined, color: c.textPrimary),
                title: Text('Save to Watch Later', style: TextStyle(color: c.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final added = await provider.toggleWatchLater(video);
                  messenger.showSnackBar(SnackBar(content: Text(added ? 'Saved to Watch Later' : 'Removed')));
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add, color: c.textPrimary),
                title: Text('Save to playlist', style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(const SnackBar(content: Text('Playlists coming soon')));
                },
              ),
              ListTile(
                leading: Icon(Icons.thumb_down_outlined, color: c.textPrimary),
                title: Text('Not interested', style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(const SnackBar(content: Text('Marked as not interested')));
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined, color: c.textPrimary),
                title: Text('Share', style: TextStyle(color: c.textPrimary)),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Channel avatar backed by a network image with a safe initials fallback.
///
/// [CachedNetworkImageProvider] exposes no widget-level errorWidget; on a 404
/// or decode failure it can throw during image resolution or render a bare
/// error circle. This resolves the stream first and swaps to the initials
/// avatar on any error, so a broken avatar URL degrades gracefully instead of
/// leaving a broken image in the card.
class _NetworkAvatar extends StatefulWidget {
  const _NetworkAvatar({
    required this.url,
    required this.radius,
    required this.backgroundColor,
    required this.fallback,
    required this.fallbackBg,
    required this.fallbackFg,
  });

  final String url;
  final double radius;
  final Color backgroundColor;
  final String fallback;
  final Color fallbackBg;
  final Color fallbackFg;

  @override
  State<_NetworkAvatar> createState() => _NetworkAvatarState();
}

class _NetworkAvatarState extends State<_NetworkAvatar> {
  ImageProvider? _provider;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final provider = CachedNetworkImageProvider(widget.url);
    // Listen for the first resolution result so we can fall back on error
    // without surfacing a broken-image widget. The listener is kept so
    // dispose() can remove it (leaving it attached leaks the stream →
    // ImageCompleter → decoded image for the widget's lifetime).
    final stream = provider.resolve(const ImageConfiguration());
    _stream = stream;
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _provider = provider;
        });
        _removeListener();
      },
      onError: (object, stackTrace) {
        if (!mounted) return;
        setState(() => _failed = true);
        _removeListener();
      },
    );
    _listener = listener;
    stream.addListener(listener);
  }

  void _removeListener() {
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) {
      s.removeListener(l);
    }
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _provider == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.fallbackBg,
        child: Text(
          widget.fallback,
          style: TextStyle(
            color: widget.fallbackFg,
            fontWeight: FontWeight.bold,
            fontSize: widget.radius * 0.78,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: _provider,
      backgroundColor: widget.backgroundColor,
    );
  }
}
