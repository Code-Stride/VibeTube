import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  final bool standalone;
  const SearchScreen({super.key, this.standalone = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String q) {
    if (q.trim().isEmpty) return;
    context.read<AppProvider>().searchVideos(q.trim());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            color: AppTheme.surface,
            child: Row(
              children: [
                if (widget.standalone)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: widget.standalone,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search VibeTube',
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.textMuted, size: 22),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _controller.clear();
                                context.read<AppProvider>().clearSearch();
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _submit,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.searchResults.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.searchQuery.isEmpty) {
                  return _suggestions(provider);
                }
                if (provider.searchResults.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 56, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text('No results',
                            style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: provider.searchResults.length,
                  itemBuilder: (context, i) {
                    final v = provider.searchResults[i];
                    return VideoCard(
                      video: v,
                      compact: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PlayerScreen(videoId: v.id, preview: v),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestions(AppProvider provider) {
    const trending = [
      'Music',
      'Bollywood',
      'Cricket',
      'Tech reviews',
      'Gaming',
      'Comedy',
      'News India',
      'Tutorials',
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Trending searches',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: trending
              .map((t) => ActionChip(
                    avatar: const Icon(Icons.trending_up, size: 16),
                    label: Text(t),
                    backgroundColor: AppTheme.surfaceLight,
                    onPressed: () {
                      _controller.text = t;
                      _submit(t);
                    },
                  ))
              .toList(),
        ),
        if (provider.history.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('Continue watching',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ...provider.history.take(6).map((v) => VideoCard(
                video: v,
                compact: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(videoId: v.id, preview: v),
                    ),
                  );
                },
              )),
        ],
      ],
    );
  }
}
