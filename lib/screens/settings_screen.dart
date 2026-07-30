import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version}+${p.buildNumber}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppTheme.surface,
            child: const Text(
              'Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, p, _) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _Header('Playback'),
                    _tile(
                      icon: Icons.block,
                      title: 'Ad blocker',
                      subtitle: 'Skip ads via client streams',
                      value: p.isAdBlockEnabled,
                      onChanged: (_) => p.toggleAdBlock(),
                    ),
                    _tile(
                      icon: Icons.skip_next,
                      title: 'SponsorBlock',
                      subtitle: 'Auto-skip sponsored segments',
                      value: p.isSponsorBlockEnabled,
                      onChanged: (_) => p.toggleSponsorBlock(),
                    ),
                    _tile(
                      icon: Icons.headphones,
                      title: 'Background play',
                      subtitle: 'Keep screen awake while playing',
                      value: p.isBackgroundPlayEnabled,
                      onChanged: (_) => p.toggleBackgroundPlay(),
                    ),
                    _tile(
                      icon: Icons.picture_in_picture_alt,
                      title: 'Auto PiP hint',
                      subtitle: 'Use system PiP with Home button',
                      value: p.isAutoPipEnabled,
                      onChanged: (_) => p.toggleAutoPip(),
                    ),
                    const SizedBox(height: 18),
                    const _Header('SponsorBlock categories'),
                    _cat(p, 'sponsor', 'Sponsor', AppTheme.sbSponsor, p.sbSponsor),
                    _cat(p, 'selfpromo', 'Self-promotion', AppTheme.sbSelfpromo, p.sbSelfpromo),
                    _cat(p, 'interaction', 'Interaction', AppTheme.sbInteraction, p.sbInteraction),
                    _cat(p, 'intro', 'Intro', AppTheme.sbIntro, p.sbIntro),
                    _cat(p, 'outro', 'Outro', AppTheme.sbOutro, p.sbOutro),
                    _cat(p, 'filler', 'Filler', AppTheme.sbFiller, p.sbFiller),
                    const SizedBox(height: 18),
                    const _Header('Appearance'),
                    _tile(
                      icon: Icons.dark_mode,
                      title: 'Dark mode',
                      subtitle: 'OLED-friendly dark theme',
                      value: p.isDarkMode,
                      onChanged: (_) => p.toggleDarkMode(),
                    ),
                    const SizedBox(height: 18),
                    const _Header('Updates'),
                    ListTile(
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.system_update,
                          color: AppTheme.primary),
                      title: const Text('Check for updates'),
                      subtitle: Text(
                        _version.isEmpty ? 'VibeTube' : 'Installed $_version',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      trailing: const Icon(Icons.chevron_right),
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
                    const SizedBox(height: 8),
                    ListTile(
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.open_in_new),
                      title: const Text('GitHub releases'),
                      onTap: () async {
                        final uri = Uri.parse(
                            'https://github.com/Code-Stride/VibeTube/releases');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
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
                          const Text('VibeTube',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            _version.isEmpty ? '…' : 'v$_version',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ad-free · SponsorBlock · Dislikes · Downloads',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 12),
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

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: AppTheme.textSecondary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _cat(AppProvider p, String key, String name, Color color, bool val) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(name),
        value: val,
        activeColor: color,
        onChanged: (v) => p.setSbCategory(key, v),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) {
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
}
