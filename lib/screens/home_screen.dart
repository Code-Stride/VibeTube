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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleUpdateCheck());
  }

  Future<void> _scheduleUpdateCheck() async {
    // Give network a moment; update check already started in provider.init
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _updateShown) return;
      final provider = context.read<AppProvider>();
      final u = provider.pendingUpdate;
      if (u != null && u.hasUpdate) {
        _updateShown = true;
        await UpdateDialog.show(
          context,
          info: u,
          onLater: () {},
          onSkip: () => provider.dismissUpdate(),
        );
        return;
      }
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

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: VibeColors.of(context).border, width: 0.6)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(
                icon: Icon(Icons.video_library_outlined),
                activeIcon: Icon(Icons.video_library),
                label: 'Library'),
            BottomNavigationBarItem(
                icon: Icon(Icons.download_outlined),
                activeIcon: Icon(Icons.download),
                label: 'Downloads'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
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
    'Music',
    'Gaming',
    'News',
    'Sports',
    'Movies',
    'Live',
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
                if (provider.isLoading && provider.trendingVideos.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.error != null && provider.trendingVideos.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              size: 52, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          Text(provider.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
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
                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: provider.loadTrending,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: provider.trendingVideos.length,
                    itemBuilder: (context, index) {
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
