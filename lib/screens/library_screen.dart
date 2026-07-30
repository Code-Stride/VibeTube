import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer<AppProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                color: AppTheme.surface,
                child: const Text(
                  'Library',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(
                      context,
                      icon: Icons.history,
                      title: 'History',
                      count: provider.history.length,
                      videos: provider.history,
                      onClear: provider.history.isEmpty
                          ? null
                          : () async {
                              await provider.clearHistory();
                            },
                    ),
                    const SizedBox(height: 18),
                    _section(
                      context,
                      icon: Icons.watch_later_outlined,
                      title: 'Watch Later',
                      count: provider.watchLater.length,
                      videos: provider.watchLater,
                    ),
                    const SizedBox(height: 18),
                    _section(
                      context,
                      icon: Icons.thumb_up_outlined,
                      title: 'Liked videos',
                      count: provider.liked.length,
                      videos: provider.liked,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Premium unlocked',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _feature(Icons.block, 'Ad-free playback'),
                    _feature(Icons.skip_next, 'SponsorBlock auto-skip'),
                    _feature(Icons.thumb_down, 'Return YouTube Dislike'),
                    _feature(Icons.speed, 'Speed control up to 3x'),
                    _feature(Icons.hd, 'Quality selection'),
                    _feature(Icons.dark_mode, 'OLED dark theme'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required List<Video> videos,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 6),
            Text('($count)',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const Spacer(),
            if (onClear != null)
              TextButton(
                onPressed: onClear,
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (videos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Nothing here yet',
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
            ),
          )
        else
          ...videos.take(8).map((v) => VideoCard(
                video: v,
                compact: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(videoId: v.id, preview: v),
                    ),
                  );
                },
              )),
      ],
    );
  }

  Widget _feature(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          ),
          const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
        ],
      ),
    );
  }
}
