import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../services/native_player.dart';
import '../utils/theme.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _pipOk = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version}+${p.buildNumber}');
    });
    NativePlayer.isPipSupported().then((v) {
      if (mounted) setState(() => _pipOk = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = VibeColors.of(context);
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: c.surface,
            child: Text(
              'Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, p, _) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _header('Playback'),
                    _tile(
                      c,
                      icon: Icons.block,
                      title: 'Ad blocker',
                      subtitle: 'Ad-free streams via InnerTube clients',
                      value: p.isAdBlockEnabled,
                      onChanged: (_) => p.toggleAdBlock(),
                    ),
                    _tile(
                      c,
                      icon: Icons.skip_next,
                      title: 'SponsorBlock',
                      subtitle: 'Auto-skip sponsored segments',
                      value: p.isSponsorBlockEnabled,
                      onChanged: (_) => p.toggleSponsorBlock(),
                    ),
                    _tile(
                      c,
                      icon: Icons.headphones,
                      title: 'Background play',
                      subtitle:
                          'Lock screen / Bluetooth / notification media controls',
                      value: p.isBackgroundPlayEnabled,
                      onChanged: (_) => p.toggleBackgroundPlay(),
                    ),
                    _tile(
                      c,
                      icon: Icons.picture_in_picture_alt,
                      title: 'Auto PiP',
                      subtitle: _pipOk
                          ? 'Home button PiP only while video is playing'
                          : 'PiP not supported on this device',
                      value: p.isAutoPipEnabled && _pipOk,
                      onChanged: !_pipOk ? null : (_) => p.toggleAutoPip(),
                    ),
                    const SizedBox(height: 18),
                    _header('SponsorBlock categories'),
                    _cat(c, p, 'sponsor', 'Sponsor', AppTheme.sbSponsor, p.sbSponsor),
                    _cat(c, p, 'selfpromo', 'Self-promotion', AppTheme.sbSelfpromo, p.sbSelfpromo),
                    _cat(c, p, 'interaction', 'Interaction', AppTheme.sbInteraction, p.sbInteraction),
                    _cat(c, p, 'intro', 'Intro', AppTheme.sbIntro, p.sbIntro),
                    _cat(c, p, 'outro', 'Outro', AppTheme.sbOutro, p.sbOutro),
                    _cat(c, p, 'filler', 'Filler', AppTheme.sbFiller, p.sbFiller),
                    const SizedBox(height: 18),
                    _header('Appearance'),
                    _tile(
                      c,
                      icon: p.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      title: 'Dark mode',
                      subtitle: p.isDarkMode
                          ? 'OLED dark theme on'
                          : 'Light theme on',
                      value: p.isDarkMode,
                      onChanged: (_) => p.toggleDarkMode(),
                    ),
                    const SizedBox(height: 18),
                    _header('Updates'),
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.system_update,
                            color: AppTheme.primary),
                        title: Text('Check for updates',
                            style: TextStyle(color: c.textPrimary)),
                        subtitle: Text(
                          _version.isEmpty ? 'VibeTube' : 'Installed $_version',
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                        trailing: Icon(Icons.chevron_right, color: c.textMuted),
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Checking…')),
                          );
                          await p.checkUpdate(force: true);
                          if (!context.mounted) return;
                          final u = p.pendingUpdate;
                          if (u != null && u.hasUpdate) {
                            await UpdateDialog.show(
                              context,
                              info: u,
                              onLater: () {},
                              onSkip: () => p.dismissUpdate(),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('You are on the latest version')),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: Icon(Icons.open_in_new, color: c.textSecondary),
                        title: Text('GitHub releases',
                            style: TextStyle(color: c.textPrimary)),
                        onTap: () async {
                          final uri = Uri.parse(
                              'https://github.com/Code-Stride/VibeTube/releases');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                AppTheme.primary,
                                AppTheme.secondary
                              ]),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 12),
                          Text('VibeTube',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary)),
                          const SizedBox(height: 4),
                          Text(
                            _version.isEmpty ? '…' : 'v$_version',
                            style: TextStyle(color: c.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'PiP · Background · HLS · SponsorBlock · Dislikes',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          const Text('Made with ❤ by BlazeNXT',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _tile(
    VibeColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: c.textSecondary),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: c.textSecondary)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _cat(VibeColors c, AppProvider p, String key, String name, Color color,
      bool val) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(name, style: TextStyle(color: c.textPrimary)),
        value: val,
        activeTrackColor: color,
        onChanged: (v) => p.setSbCategory(key, v),
      ),
    );
  }
}
