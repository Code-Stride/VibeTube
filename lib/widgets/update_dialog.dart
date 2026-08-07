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
      builder: (_) =>
          UpdateDialog(info: info, onLater: onLater, onSkip: onSkip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = VibeColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
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
            child:
                const Icon(Icons.system_update, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: c.textPrimary),
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
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current',
                          style: TextStyle(color: c.textMuted, fontSize: 11)),
                      Text(info.currentVersion,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward,
                    color: AppTheme.primary, size: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Latest',
                          style: TextStyle(color: c.textMuted, fontSize: 11)),
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
          Text("What's new",
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: c.textPrimary)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: Text(
                info.releaseNotes.isEmpty
                    ? 'Bug fixes, performance improvements and new features.'
                    : info.releaseNotes,
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13, height: 1.4),
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
          child: Text('Later', style: TextStyle(color: c.textSecondary)),
        ),
        if (onSkip != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onSkip!();
            },
            child: Text('Skip', style: TextStyle(color: c.textMuted)),
          ),
        ElevatedButton.icon(
          onPressed: () async {
            // Previously: if canLaunchUrl() returned false, nothing at all
            // happened and the dialog stayed put, looking like a dead button.
            final messenger = ScaffoldMessenger.maybeOf(context);
            final navigator = Navigator.of(context);
            var ok = false;
            try {
              ok = await launchUrl(
                Uri.parse(info.downloadUrl),
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              ok = false;
            }
            if (ok) {
              navigator.pop();
            } else {
              messenger?.showSnackBar(
                const SnackBar(content: Text('Could not start the download')),
              );
            }
          },
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Update'),
        ),
      ],
    );
  }
}
