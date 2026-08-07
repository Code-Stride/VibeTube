import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/mini_player_controller.dart';
import '../screens/player_screen.dart';
import '../utils/theme.dart';

/// YouTube-exact bottom mini player.
class MiniPlayerBar extends StatelessWidget {
  final bool embedded;
  const MiniPlayerBar({super.key, this.embedded = false});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    return Consumer<MiniPlayerController>(
      builder: (context, mini, _) {
        if (!mini.showMiniBar) return const SizedBox.shrink();
        final v = mini.video!;
        final c = VibeColors.of(context);
        final ctrl = mini.controller;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final progress = (ctrl != null && ctrl.value.isInitialized && ctrl.value.duration.inMilliseconds > 0)
            ? ctrl.value.position.inMilliseconds / ctrl.value.duration.inMilliseconds
            : 0.0;

        return Material(
          color: isDark ? const Color(0xFF212121) : Colors.white,
          elevation: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar (YouTube-exact: thin, at top of mini player)
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
                  valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                  minHeight: 2,
                ),
              ),
              Dismissible(
                // Keyed on the video alone: including the controller's
                // hashCode rebuilt the tile (and cancelled an in-progress
                // swipe) whenever the session object changed identity.
                key: ValueKey('mini-${v.id}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => mini.close(),
                background: Container(color: AppTheme.error, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: const Icon(Icons.close, color: Colors.white)),
                secondaryBackground: Container(color: AppTheme.error, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.close, color: Colors.white)),
                child: InkWell(
                  onTap: () => _expand(context, mini),
                  child: SizedBox(
                    height: height,
                    child: Row(
                      children: [
                        // Video thumbnail
                        SizedBox(
                          width: 114,
                          height: height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (mini.isReady && ctrl != null)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  clipBehavior: Clip.hardEdge,
                                  child: SizedBox(
                                    width: ctrl.value.size.width > 0 ? ctrl.value.size.width : 160,
                                    height: ctrl.value.size.height > 0 ? ctrl.value.size.height : 90,
                                    child: VideoPlayer(ctrl),
                                  ),
                                )
                              else if (v.thumbnailUrl.isNotEmpty)
                                CachedNetworkImage(imageUrl: v.thumbnailUrl, fit: BoxFit.cover)
                              else
                                Container(color: c.surfaceLight),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Title + channel
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: c.textPrimary)),
                              const SizedBox(height: 2),
                              Text(v.channelName.isEmpty ? 'VibeTube' : v.channelName,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.textSecondary)),
                            ],
                          ),
                        ),
                        // Play/Pause
                        IconButton(
                          icon: Icon(mini.isPlaying ? Icons.pause : Icons.play_arrow, color: c.textPrimary, size: 28),
                          onPressed: () => mini.togglePlay(),
                        ),
                        // Close
                        IconButton(
                          icon: Icon(Icons.close, color: c.textSecondary, size: 22),
                          onPressed: () => mini.close(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _expand(BuildContext context, MiniPlayerController mini) {
    final v = mini.video;
    if (v == null) return;
    mini.setExpanded(true);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PlayerScreen(videoId: v.id, preview: v, resumeSession: true),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}
