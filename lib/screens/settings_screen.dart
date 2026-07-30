import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                const Icon(Icons.settings, color: AppTheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Settings',
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
                // General section
                const _SectionHeader(title: 'General'),
                Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    return Column(
                      children: [
                        _buildSwitch(
                          icon: Icons.dark_mode,
                          title: 'Dark Mode',
                          subtitle: 'Use dark theme',
                          value: provider.isDarkMode,
                          onChanged: (_) => provider.toggleDarkMode(),
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Player section
                const _SectionHeader(title: 'Player'),
                Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    return Column(
                      children: [
                        _buildSwitch(
                          icon: Icons.block,
                          title: 'Ad Blocker',
                          subtitle: 'Block all video ads',
                          value: provider.isAdBlockEnabled,
                          onChanged: (_) => provider.toggleAdBlock(),
                        ),
                        _buildSwitch(
                          icon: Icons.skip_next,
                          title: 'SponsorBlock',
                          subtitle: 'Skip sponsored segments',
                          value: provider.isSponsorBlockEnabled,
                          onChanged: (_) => provider.toggleSponsorBlock(),
                        ),
                        _buildSwitch(
                          icon: Icons.music_note,
                          title: 'Background Play',
                          subtitle: 'Play in background',
                          value: provider.isBackgroundPlayEnabled,
                          onChanged: (_) => provider.toggleBackgroundPlay(),
                        ),
                        _buildSwitch(
                          icon: Icons.picture_in_picture,
                          title: 'Auto PiP',
                          subtitle: 'Picture-in-Picture mode',
                          value: provider.isAutoPipEnabled,
                          onChanged: (_) => provider.toggleAutoPip(),
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 24),
                
                // SponsorBlock section
                const _SectionHeader(title: 'SponsorBlock Categories'),
                _buildCategory('Sponsor', '00D400', true),
                _buildCategory('Self-Promotion', 'FFFF00', true),
                _buildCategory('Interaction Reminder', 'CC00FF', true),
                _buildCategory('Intro', '00FFFF', false),
                _buildCategory('Outro', '0202ED', false),
                _buildCategory('Filler', '7300FF', false),
                
                const SizedBox(height: 24),
                
                // About section
                const _SectionHeader(title: 'About'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Logo
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.primary, AppTheme.secondary],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'VibeTube',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Version 1.0.0',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'YouTube Premium Features Unlocked',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Made with ❤️ by BlazeNXT',
                        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
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

  Widget _buildSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textSecondary),
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
        ),
        tileColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCategory(String name, String colorHex, bool enabled) {
    final color = Color(int.parse('FF$colorHex', radix: 16));
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(name, style: const TextStyle(color: AppTheme.textPrimary)),
        trailing: Switch(
          value: enabled,
          onChanged: (val) {},
          activeColor: color,
        ),
        tileColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
