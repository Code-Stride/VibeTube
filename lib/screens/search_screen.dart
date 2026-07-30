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
    final c = VibeColors.of(context);
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            color: c.surface,
            child: Row(
              children: [
                if (widget.standalone)
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: widget.standalone,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search VibeTube',
                      hintStyle: TextStyle(color: c.textMuted),
                      prefixIcon:
                          Icon(Icons.search, color: c.textMuted, size: 22),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.close, size: 18, color: c.textMuted),
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
                  return _suggestions(provider, c);
                }
                if (provider.searchResults.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 56, color: c.textMuted),
                        const SizedBox(height: 12),
                        Text('No results',
                            style: TextStyle(color: c.textSecondary)),
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

  Widget _suggestions(AppProvider provider, VibeColors c) {
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
        Text('Trending searches',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16, color: c.textPrimary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: trending
              .map((t) => ActionChip(
                    avatar: Icon(Icons.trending_up, size: 16, color: c.textSecondary),
                    label: Text(t, style: TextStyle(color: c.textPrimary)),
                    backgroundColor: c.surfaceLight,
                    onPressed: () {
                      _controller.text = t;
                      _submit(t);
                    },
                  ))
              .toList(),
        ),
        if (provider.history.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Continue watching',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: c.textPrimary)),
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
