import 'package:flutter/material.dart';
import '../utils/theme.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // App Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppTheme.surface,
            child: Row(
              children: [
                const Icon(Icons.library_books, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Library',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // History
                _buildSection(
                  icon: Icons.history,
                  title: 'History',
                  subtitle: 'Videos you\'ve watched',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                
                // Playlists
                _buildSection(
                  icon: Icons.playlist_play,
                  title: 'Playlists',
                  subtitle: 'Your saved playlists',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                
                // Watch Later
                _buildSection(
                  icon: Icons.watch_later,
                  title: 'Watch Later',
                  subtitle: 'Videos saved for later',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                
                // Liked Videos
                _buildSection(
                  icon: Icons.thumb_up,
                  title: 'Liked Videos',
                  subtitle: 'Videos you\'ve liked',
                  onTap: () {},
                ),
                const SizedBox(height: 24),
                
                // Premium Features section
                const Text(
                  'Premium Features',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                _buildFeature(Icons.block, 'Ad-Free', 'No ads anywhere'),
                _buildFeature(Icons.music_note, 'Background Play', 'Play with screen off'),
                _buildFeature(Icons.picture_in_picture, 'PiP Mode', 'Picture in picture'),
                _buildFeature(Icons.skip_next, 'SponsorBlock', 'Skip sponsors'),
                _buildFeature(Icons.thumb_down, 'Return Dislike', 'See dislike counts'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textPrimary, size: 28),
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      onTap: onTap,
      tileColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildFeature(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
        ],
      ),
    );
  }
}
