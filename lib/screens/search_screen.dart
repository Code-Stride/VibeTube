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
  void initState() {
    super.initState();
    if (widget.standalone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String q) {
    if (q.trim().isEmpty) return;
    context.read<AppProvider>().searchVideos(q.trim());
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = VibeColors.of(context);
    return SafeArea(
      child: Column(
        children: [
          // YouTube-style search bar at top
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            color: c.surface,
            child: Row(
              children: [
                if (widget.standalone)
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                // Logo (only in tab mode)
                if (!widget.standalone) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, Color(0xFFFF8A5B)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border, width: 0.5),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: widget.standalone,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: c.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search VibeTube',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
                        prefixIcon:
                            Icon(Icons.search, color: c.textMuted, size: 20),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close,
                                    size: 18, color: c.textMuted),
                                onPressed: () {
                                  _controller.clear();
                                  context.read<AppProvider>().clearSearch();
                                  setState(() {});
                                },
                              ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0, vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _submit,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Voice search icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.mic, size: 20, color: c.textPrimary),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Voice search coming soon')),
                      );
                    },
                    padding: EdgeInsets.zero,
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
                        Text('No results found',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Try different keywords',
                            style: TextStyle(color: c.textMuted)),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Results count
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Text(
                        '${provider.searchResults.length} results',
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
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
                      ),
                    ),
                  ],
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
        Row(
          children: [
            Icon(Icons.trending_up, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Trending searches',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: c.textPrimary)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: trending
              .map((t) => ActionChip(
                    avatar:
                        Icon(Icons.trending_up, size: 16, color: c.textSecondary),
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
          Row(
            children: [
              Icon(Icons.history, size: 20, color: c.textSecondary),
              const SizedBox(width: 8),
              Text('Continue watching',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: c.textPrimary)),
            ],
          ),
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
