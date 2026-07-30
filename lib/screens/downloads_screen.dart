import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
              'Downloads',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary),
            ),
          ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                final active = provider.downloadingIds.toList();
                if (provider.downloads.isEmpty && active.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_done_rounded,
                              size: 56, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text('No downloads yet',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary)),
                          const SizedBox(height: 6),
                          Text(
                            'Open a video → tap Download.\nFiles are saved offline in the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    ...active.map((id) {
                      final p = provider.downloadProgress[id] ?? 0;
                      return Card(
                        color: c.surface,
                        child: ListTile(
                          leading: const CircularProgressIndicator(strokeWidth: 2),
                          title: Text('Downloading…',
                              style: TextStyle(color: c.textPrimary)),
                          subtitle: LinearProgressIndicator(value: p),
                          trailing: Text('${(p * 100).toStringAsFixed(0)}%',
                              style: TextStyle(color: c.textSecondary)),
                        ),
                      );
                    }),
                    ...provider.downloads.map((v) {
                      return Dismissible(
                        key: ValueKey(v.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: AppTheme.error,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => provider.removeDownload(v.id),
                        child: VideoCard(
                          video: v,
                          compact: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlayerScreen(
                                  videoId: v.id,
                                  preview: v,
                                  localPath: v.localPath.isNotEmpty
                                      ? v.localPath
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
