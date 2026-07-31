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
      child: Consumer<AppProvider>(
        builder: (context, p, _) {
          return CustomScrollView(
            slivers: [
              // App bar
              SliverAppBar(
                floating: true,
                pinned: false,
                backgroundColor: c.surface,
                title: Text('Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    )),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ---- Account Section ----
                    _accountCard(c),
                    const SizedBox(height: 20),

                    // ---- Playback Section ----
                    _sectionHeader('Playback', Icons.play_circle_outline),
                    const SizedBox(height: 8),
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
                          'Screen-off audio + lock screen / Bluetooth media controls',
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
                      onChanged:
                          !_pipOk ? null : (_) => p.toggleAutoPip(),
                    ),
                    _tile(
                      c,
                      icon: Icons.closed_caption,
                      title: 'Captions',
                      subtitle: 'Show subtitles when available',
                      value: p.isCaptionsEnabled,
                      onChanged: (_) => p.toggleCaptions(),
                    ),
                    const SizedBox(height: 20),

                    // ---- SponsorBlock Categories ----
                    _sectionHeader(
                        'SponsorBlock categories', Icons.category),
                    const SizedBox(height: 8),
                    _cat(c, p, 'sponsor', 'Sponsor',
                        AppTheme.sbSponsor, p.sbSponsor),
                    _cat(c, p, 'selfpromo', 'Self-promotion',
                        AppTheme.sbSelfpromo, p.sbSelfpromo),
                    _cat(c, p, 'interaction', 'Interaction',
                        AppTheme.sbInteraction, p.sbInteraction),
                    _cat(c, p, 'intro', 'Intro',
                        AppTheme.sbIntro, p.sbIntro),
                    _cat(c, p, 'outro', 'Outro',
                        AppTheme.sbOutro, p.sbOutro),
                    _cat(c, p, 'filler', 'Filler',
                        AppTheme.sbFiller, p.sbFiller),
                    const SizedBox(height: 20),

                    // ---- Appearance ----
                    _sectionHeader('Appearance', Icons.palette),
                    const SizedBox(height: 8),
                    _tile(
                      c,
                      icon: p.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode,
                      title: 'Dark mode',
                      subtitle: p.isDarkMode
                          ? 'OLED dark theme on'
                          : 'Light theme on',
                      value: p.isDarkMode,
                      onChanged: (_) => p.toggleDarkMode(),
                    ),
                    const SizedBox(height: 20),

                    // ---- Quality & Speed ----
                    _sectionHeader('Default settings', Icons.tune),
                    const SizedBox(height: 8),
                    _settingTile(
                      c,
                      icon: Icons.high_quality,
                      title: 'Default quality',
                      value: p.defaultQuality,
                      onTap: () => _showDefaultQualitySheet(p),
                    ),
                    _settingTile(
                      c,
                      icon: Icons.speed,
                      title: 'Default speed',
                      value: '${p.defaultSpeed}x',
                      onTap: () => _showDefaultSpeedSheet(p),
                    ),
                    _settingTile(
                      c,
                      icon: Icons.language,
                      title: 'Region',
                      value: p.region,
                      onTap: () => _showRegionSheet(p),
                    ),
                    const SizedBox(height: 20),

                    // ---- Updates ----
                    _sectionHeader('Updates', Icons.system_update),
                    const SizedBox(height: 8),
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.system_update,
                            color: AppTheme.primary),
                        title: Text('Check for updates',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary)),
                        subtitle: Text(
                          _version.isEmpty
                              ? 'VibeTube'
                              : 'Installed $_version',
                          style: TextStyle(
                              fontSize: 12, color: c.textSecondary),
                        ),
                        trailing:
                            Icon(Icons.chevron_right, color: c.textMuted),
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
                                  content: Text(
                                      'You are on the latest version')),
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
                        leading: Icon(Icons.open_in_new,
                            color: c.textSecondary),
                        title: Text('GitHub releases',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary)),
                        trailing:
                            Icon(Icons.chevron_right, color: c.textMuted),
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

                    // ---- About ----
                    _sectionHeader('About', Icons.info_outline),
                    const SizedBox(height: 8),
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
                            'PiP · Background · HLS · SponsorBlock · Dislikes · Captions',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: c.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          const Text('Made with ❤ by BlazeNXT',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _accountCard(VibeColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.15),
            AppTheme.secondary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFFFF8A5B)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VibeTube Premium',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: c.textPrimary)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'UNLOCKED',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: AppTheme.success, size: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
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
            style: TextStyle(
                fontWeight: FontWeight.w600, color: c.textPrimary)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: c.textSecondary)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _settingTile(
    VibeColors c, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: c.textSecondary),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: c.textPrimary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: c.textMuted, size: 20),
          ],
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }

  Widget _cat(VibeColors c, AppProvider p, String key, String name,
      Color color, bool val) {
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

  void _showDefaultQualitySheet(AppProvider p) {
    final c = VibeColors.of(context);
    final qs = ['Auto (HLS)', '1080p', '720p', '480p', '360p', 'Audio Only'];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Default quality',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: c.textPrimary)),
            ),
            ...qs.map((q) => ListTile(
                  title: Text(q,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: p.defaultQuality == q
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
                  trailing: p.defaultQuality == q
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    p.setDefaultQuality(q);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showDefaultSpeedSheet(AppProvider p) {
    final c = VibeColors.of(context);
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Default speed',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: c.textPrimary)),
            ),
            ...speeds.map((s) => ListTile(
                  title: Text('${s}x',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: (p.defaultSpeed - s).abs() < 0.01
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
                  subtitle: s == 1.0
                      ? Text('Normal',
                          style:
                              TextStyle(color: c.textMuted, fontSize: 12))
                      : null,
                  trailing: (p.defaultSpeed - s).abs() < 0.01
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    p.setDefaultSpeed(s);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRegionSheet(AppProvider p) {
    final c = VibeColors.of(context);
    final regions = ['IN', 'US', 'GB', 'JP', 'KR', 'BR', 'DE', 'FR'];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Region',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: c.textPrimary)),
            ),
            ...regions.map((r) => ListTile(
                  title: Text(r,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: p.region == r
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
                  trailing: p.region == r
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    p.setRegion(r);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
