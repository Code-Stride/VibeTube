import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import '../widgets/update_dialog.dart';
import 'search_screen.dart';
import 'player_screen.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';
import 'shorts_screen.dart';
import '../providers/mini_player_controller.dart';
import '../widgets/mini_player_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _updateShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MiniPlayerController>().setUseGlobalOverlay(false);
      _scheduleUpdateCheck();
    });
  }

  @override
  void dispose() {
    try { context.read<MiniPlayerController>().setUseGlobalOverlay(true); } catch (_) {}
    super.dispose();
  }

  Future<void> _scheduleUpdateCheck() async {
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted || _updateShown) return;
    final provider = context.read<AppProvider>();
    final u = provider.pendingUpdate;
    if (u != null && u.hasUpdate) {
      _updateShown = true;
      if (!mounted) return;
      await UpdateDialog.show(context, info: u,
        onLater: () { _updateShown = false; },
        onSkip: () { provider.dismissUpdate(); _updateShown = false; },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _HomeFeed(),
      const SearchScreen(),
      ShortsScreen(isActive: _index == 2),
      const LibraryScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    final showMini = context.watch<MiniPlayerController>().showMiniBar;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: IndexedStack(key: ValueKey(_index), index: _index, children: pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMini) const MiniPlayerBar(embedded: true),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF303030) : const Color(0xFFE0E0E0), width: 0.5)),
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: 'Shorts'),
                BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), label: 'Library'),
                BottomNavigationBarItem(icon: Icon(Icons.download_outlined), label: 'Downloads'),
                BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeFeed extends StatefulWidget {
  const _HomeFeed();

  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  static const cats = ['All', 'Music', 'Gaming', 'News', 'Sports', 'Live', 'Movies', 'Education', 'Technology', 'Comedy'];

  @override
  Widget build(BuildContext context) {
    final c = VibeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          // YouTube-exact top bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            color: c.surface,
            child: Row(
              children: [
                // YouTube logo
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill, color: AppTheme.primary, size: 28),
                    const SizedBox(width: 4),
                    Text('VibeTube', style: TextStyle(
                      color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5,
                    )),
                  ],
                ),
                const Spacer(),
                // Cast, notifications, search
                IconButton(icon: Icon(Icons.cast, size: 22, color: c.textPrimary), onPressed: () {}),
                IconButton(icon: Icon(Icons.notifications_outlined, size: 22, color: c.textPrimary), onPressed: () {}),
                IconButton(
                  icon: Icon(Icons.search, size: 22, color: c.textPrimary),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen(standalone: true)));
                  },
                ),
                // Profile avatar
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
          // Category chips (YouTube-exact)
          Container(
            height: 44,
            color: c.surface,
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final cat = cats[i];
                    final selected = provider.selectedCategory == cat;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (_) => provider.setCategory(cat),
                        showCheckmark: false,
                        selectedColor: isDark ? Colors.white : const Color(0xFF0F0F0F),
                        backgroundColor: isDark ? const Color(0xFF272727) : const Color(0xFFF2F2F2),
                        labelStyle: TextStyle(
                          color: selected
                              ? (isDark ? Colors.black : Colors.white)
                              : c.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Feed
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.trendingVideos.isEmpty) {
                  return _buildShimmer(c);
                }
                if (provider.error != null && provider.trendingVideos.isEmpty) {
                  return _buildError(provider, c);
                }
                if (provider.trendingVideos.isEmpty) {
                  return _buildEmpty(c);
                }
                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: provider.loadTrending,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: provider.trendingVideos.length + (provider.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= provider.trendingVideos.length) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final video = provider.trendingVideos[index];
                      return VideoCard(
                        video: video,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PlayerScreen(videoId: video.id, preview: video),
                          ));
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(VibeColors c) {
    return ListView.builder(
      padding: const EdgeInsets.all(0),
      itemCount: 4,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 200,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            color: c.surfaceLight,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 18, backgroundColor: c.surfaceLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: double.infinity, height: 16, color: c.surfaceLight),
                      const SizedBox(height: 6),
                      Container(width: 120, height: 14, color: c.surfaceLight),
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

  Widget _buildError(AppProvider provider, VibeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: c.textMuted),
            const SizedBox(height: 16),
            Text(provider.error!, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: provider.loadTrending, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(VibeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 48, color: c.textMuted),
          const SizedBox(height: 16),
          Text('No videos found', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.read<AppProvider>().loadTrending(), child: const Text('Refresh')),
        ],
      ),
    );
  }
}
