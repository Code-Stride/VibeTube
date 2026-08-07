import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

/// YouTube-exact search screen.
class SearchScreen extends StatefulWidget {
  final bool standalone;
  const SearchScreen({super.key, this.standalone = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.standalone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 1200) {
      context.read<AppProvider>().loadMoreSearch();
    }
  }

  void _submit(String q) {
    if (q.trim().isEmpty) return;
    context.read<AppProvider>().searchVideos(q.trim());
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = VibeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // YouTube-exact search bar
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              color: c.surface,
              child: Row(
                children: [
                  if (widget.standalone)
                    IconButton(icon: Icon(Icons.arrow_back, color: c.textPrimary), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121212) : const Color(0xFFF1F1F1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: widget.standalone,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(color: c.textPrimary, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 16),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            child: Icon(Icons.search, color: c.textMuted, size: 20),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close, size: 20, color: c.textMuted),
                                  onPressed: () {
                                    _controller.clear();
                                    context.read<AppProvider>().clearSearch();
                                    setState(() {});
                                  },
                                ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _submit,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF272727) : const Color(0xFFF2F2F2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.mic, size: 20, color: c.textPrimary),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice search coming soon')));
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Results
            Expanded(
              child: Consumer<AppProvider>(
                builder: (context, provider, _) {
                  // Uses the search-specific flag: the shared `isLoading`
                  // meant a Home-feed refresh put a spinner over the search
                  // results (and vice versa).
                  if (provider.isSearching && provider.searchResults.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.searchQuery.isEmpty) return _suggestions(provider, c);
                  if (provider.searchError != null && provider.searchResults.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(provider.searchError!,
                              style: TextStyle(color: c.textSecondary, fontSize: 16)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => provider.searchVideos(provider.searchQuery),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.searchResults.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text('No results found', style: TextStyle(color: c.textSecondary, fontSize: 16)),
                        ],
                      ),
                    );
                  }
                  final showFooter =
                      provider.isLoadingMoreSearch || provider.hasMoreSearch;
                  return ListView.builder(
                    controller: _scroll,
                    itemCount: provider.searchResults.length + (showFooter ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= provider.searchResults.length) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final v = provider.searchResults[i];
                      return VideoCard(
                        video: v, compact: true,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => PlayerScreen(videoId: v.id, preview: v))),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestions(AppProvider provider, VibeColors c) {
    const trending = ['Music', 'Bollywood', 'Cricket', 'Tech reviews', 'Gaming', 'Comedy', 'News India', 'Tutorials'];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Search History (YouTube-style)
        if (provider.searchHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: c.textPrimary),
                const SizedBox(width: 12),
                Expanded(child: Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: c.textPrimary))),
                TextButton(
                  onPressed: () => _showClearSearchHistoryDialog(provider, c),
                  child: Text('Clear all', style: TextStyle(color: AppTheme.secondary, fontSize: 14)),
                ),
              ],
            ),
          ),
          ...provider.searchHistory.take(10).map((query) => ListTile(
            leading: Icon(Icons.history, size: 20, color: c.textSecondary),
            title: Text(query, style: TextStyle(color: c.textPrimary, fontSize: 16)),
            trailing: IconButton(
              icon: Icon(Icons.close, size: 18, color: c.textMuted),
              onPressed: () => provider.removeSearchQuery(query),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () { _controller.text = query; _submit(query); },
          )),
          Divider(height: 1, color: c.border),
        ],
        // Trending
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.trending_up, size: 20, color: c.textPrimary),
              const SizedBox(width: 12),
              Text('Trending searches', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: c.textPrimary)),
            ],
          ),
        ),
        ...trending.map((t) => ListTile(
          leading: Icon(Icons.trending_up, size: 20, color: c.textSecondary),
          title: Text(t, style: TextStyle(color: c.textPrimary, fontSize: 16)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          onTap: () { _controller.text = t; _submit(t); },
        )),
        // Continue watching
        if (provider.history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.play_circle_outline, size: 20, color: c.textPrimary),
                const SizedBox(width: 12),
                Text('Continue watching', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: c.textPrimary)),
              ],
            ),
          ),
          ...provider.history.take(6).map((v) => VideoCard(
            video: v, compact: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PlayerScreen(videoId: v.id, preview: v))),
          )),
        ],
      ],
    );
  }

  void _showClearSearchHistoryDialog(AppProvider provider, VibeColors c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Clear search history?', style: TextStyle(color: c.textPrimary, fontSize: 20)),
        content: Text('Your search history will be cleared from this device.', style: TextStyle(color: c.textSecondary, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.textSecondary))),
          TextButton(
            onPressed: () { provider.clearSearchHistory(); Navigator.pop(ctx); },
            child: const Text('Clear all', style: TextStyle(color: AppTheme.secondary)),
          ),
        ],
      ),
    );
  }
}
