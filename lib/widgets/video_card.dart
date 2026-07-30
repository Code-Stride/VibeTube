import 'package:flutter/material.dart';
import '../api/innertube_client.dart';
import '../utils/theme.dart';

class VideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  
  const VideoCard({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // Thumbnail
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  image: video.thumbnailUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(video.thumbnailUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: video.thumbnailUrl.isEmpty
                    ? const Center(
                        child: Icon(Icons.play_circle_outline, color: AppTheme.textMuted, size: 48),
                      )
                    : null,
              ),
              // Duration badge
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    video.formattedDuration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.surfaceLight,
                  child: Text(
                    video.channelName.isNotEmpty ? video.channelName[0].toUpperCase() : 'C',
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Title and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.channelName} • ${video.formattedViewCount} views • ${video.publishedAt}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // More options
                IconButton(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                  onPressed: () {
                    _showVideoOptions(context);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.surfaceLight),
        ],
      ),
    );
  }

  void _showVideoOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Video Options',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildOption(Icons.download, 'Download', () {}),
          _buildOption(Icons.playlist_add, 'Save to Playlist', () {}),
          _buildOption(Icons.share, 'Share', () {}),
          _buildOption(Icons.block, 'Not Interested', () {}),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOption(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textPrimary),
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
      onTap: onTap,
    );
  }
}
