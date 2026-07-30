import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/video.dart';
import '../utils/theme.dart';

class UpdateDialog extends StatelessWidget {
  final AppUpdateInfo info;
  final VoidCallback onLater;
  final VoidCallback? onSkip;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.onLater,
    this.onSkip,
  });

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo info,
    required VoidCallback onLater,
    VoidCallback? onSkip,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info, onLater: onLater, onSkip: onSkip),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.secondary],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 11)),
                      Text(info.currentVersion,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: AppTheme.primary, size: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Latest',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 11)),
                      Text('v${info.latestVersion}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text("What's new",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: Text(
                info.releaseNotes.isEmpty
                    ? 'Bug fixes, performance improvements and new features.'
                    : info.releaseNotes,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onLater();
          },
          child: const Text('Later', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        if (onSkip != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onSkip!();
            },
            child: const Text('Skip', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ElevatedButton.icon(
          onPressed: () async {
            final uri = Uri.parse(info.downloadUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Update'),
        ),
      ],
    );
  }
}
