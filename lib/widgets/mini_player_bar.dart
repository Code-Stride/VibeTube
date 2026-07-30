import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/mini_player_controller.dart';
import '../screens/player_screen.dart';
import '../utils/theme.dart';

/// YouTube-style bottom mini player — tap to expand, swipe to dismiss.
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
        final progress = (ctrl != null &&
                ctrl.value.isInitialized &&
                ctrl.value.duration.inMilliseconds > 0)
            ? ctrl.value.position.inMilliseconds /
                ctrl.value.duration.inMilliseconds
            : 0.0;

        final content = Material(
          color: c.surface,
          elevation: embedded ? 6 : 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 2.5,
                backgroundColor: c.border,
                color: AppTheme.primary,
              ),
              Dismissible(
                key: ValueKey('mini-${v.id}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => mini.close(),
                background: Container(
                  color: AppTheme.error.withValues(alpha: 0.9),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: AppTheme.error.withValues(alpha: 0.9),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
                child: InkWell(
                  onTap: () => _expand(context, mini),
                  child: SizedBox(
                    height: height,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 114,
                          height: height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (mini.isReady)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  clipBehavior: Clip.hardEdge,
                                  child: SizedBox(
                                    width: ctrl!.value.size.width > 0
                                        ? ctrl.value.size.width
                                        : 160,
                                    height: ctrl.value.size.height > 0
                                        ? ctrl.value.size.height
                                        : 90,
                                    child: VideoPlayer(ctrl),
                                  ),
                                )
                              else if (v.thumbnailUrl.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: v.thumbnailUrl,
                                  fit: BoxFit.cover,
                                )
                              else
                                Container(color: c.surfaceLight),
                              Container(
                                color: Colors.black.withValues(alpha: 0.12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v.channelName.isEmpty
                                    ? 'VibeTube'
                                    : v.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: mini.isPlaying ? 'Pause' : 'Play',
                          icon: Icon(
                            mini.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: c.textPrimary,
                            size: 28,
                          ),
                          onPressed: () => mini.togglePlay(),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: Icon(Icons.close_rounded,
                              color: c.textSecondary, size: 22),
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

        if (embedded) return content;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: content,
            ),
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
        pageBuilder: (_, __, ___) => PlayerScreen(
          videoId: v.id,
          preview: v,
          resumeSession: true,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }
}
