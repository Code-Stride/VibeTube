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
    // Leaving main shell (shouldn't often) — allow global mini
    try {
      context.read<MiniPlayerController>().setUseGlobalOverlay(true);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _scheduleUpdateCheck() async {
    // Wait for the provider's async update check to complete, then show dialog
    // instead of polling in a loop.
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted || _updateShown) return;
    final provider = context.read<AppProvider>();
    final u = provider.pendingUpdate;
    if (u != null && u.hasUpdate) {
      _updateShown = true;
      if (!mounted) return;
      await UpdateDialog.show(
        context,
        info: u,
        onLater: () {
          // Reset so user can be prompted again later in the session
          _updateShown = false;
        },
        onSkip: () {
          provider.dismissUpdate();
          _updateShown = false;
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _HomeFeed(),
      const SearchScreen(),
      const LibraryScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    final showMini = context.watch<MiniPlayerController>().showMiniBar;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMini) const MiniPlayerBar(embedded: true),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: VibeColors.of(context).border,
                  width: 0.6,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.video_library_outlined),
                  activeIcon: Icon(Icons.video_library),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_outlined),
                  activeIcon: Icon(Icons.download),
                  label: 'Downloads',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
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
  static const cats = [
    'All',
    'Shorts',
    'Music',
    'Gaming',
    'News',
    'Sports',
    'Live',
    'Movies',
    'Education',
    'Technology',
    'Comedy',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(
              color: VibeColors.of(context).surface,
              border: Border(bottom: BorderSide(color: VibeColors.of(context).border, width: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primary, Color(0xFFFF8A5B)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'VibeTube',
                  style: TextStyle(
                    color: VibeColors.of(context).textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PREMIUM',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchScreen(standalone: true)),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = cats[i];
                    final selected = provider.selectedCategory == c;
                    return FilterChip(
                      label: Text(c),
                      selected: selected,
                      onSelected: (_) => provider.setCategory(c),
                      showCheckmark: false,
                      selectedColor: AppTheme.primary,
                      backgroundColor: VibeColors.of(context).surfaceLight,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : VibeColors.of(context).textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                );
              },
            ),
          ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                final c = VibeColors.of(context);
                if (provider.isLoading && provider.trendingVideos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          provider.selectedCategory == 'All'
                              ? 'Loading feed…'
                              : 'Loading ${provider.selectedCategory}…',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                if (provider.error != null && provider.trendingVideos.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 52, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(provider.error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: provider.loadTrending,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (provider.trendingVideos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_library_outlined,
                            size: 52, color: c.textMuted),
                        const SizedBox(height: 12),
                        Text('Nothing here yet',
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: provider.loadTrending,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: provider.loadTrending,
                  child: Stack(
                    children: [
                      ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: provider.trendingVideos.length +
                            (provider.isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= provider.trendingVideos.length) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final video = provider.trendingVideos[index];
                          return VideoCard(
                            video: video,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlayerScreen(
                                    videoId: video.id,
                                    preview: video,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      if (provider.isLoading && provider.trendingVideos.isNotEmpty)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
