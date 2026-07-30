import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';

class PlayerScreen extends StatefulWidget {
  final String videoId;
  
  const PlayerScreen({super.key, required this.videoId});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  double _playbackSpeed = 1.0;
  String _selectedQuality = 'Auto';
  bool _isSponsorBlockEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    final provider = context.read<AppProvider>();
    await provider.loadVideoDetails(widget.videoId);
    
    if (provider.currentVideo != null) {
      // Find a working video URL
      final formats = provider.currentVideo!.formats;
      String? videoUrl;
      
      for (var format in formats) {
        if (format.url.isNotEmpty && !format.isVideoOnly) {
          videoUrl = format.url;
          break;
        }
      }
      
      if (videoUrl != null) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
          ..initialize().then((_) {
            setState(() {
              _isInitialized = true;
            });
            _controller?.play();
          });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final video = provider.currentVideo;
          
          return Column(
            children: [
              // Video Player
              Stack(
                children: [
                  // Video
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _isInitialized && _controller != null
                        ? VideoPlayer(_controller!)
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(color: AppTheme.primary),
                            ),
                          ),
                  ),
                  
                  // Controls overlay
                  if (_showControls)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top controls
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  const Spacer(),
                                  // SponsorBlock indicator
                                  if (_isSponsorBlockEnabled)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.sbSponsor.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.skip_next, size: 16, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text('SB', style: TextStyle(color: Colors.white, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.download, color: Colors.white),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ),
                            
                            // Center play button
                            IconButton(
                              icon: Icon(
                                _controller?.value.isPlaying == true
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                size: 64,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller?.value.isPlaying == true) {
                                    _controller?.pause();
                                  } else {
                                    _controller?.play();
                                  }
                                });
                              },
                            ),
                            
                            // Bottom controls
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Speed
                                  TextButton(
                                    onPressed: _showSpeedDialog,
                                    child: Text(
                                      '${_playbackSpeed}x',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  
                                  // Quality
                                  TextButton(
                                    onPressed: _showQualityDialog,
                                    child: Text(
                                      _selectedQuality,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  
                                  const Spacer(),
                                  
                                  // Background play
                                  IconButton(
                                    icon: const Icon(Icons.music_note, color: Colors.white),
                                    onPressed: () {},
                                  ),
                                  
                                  // PiP
                                  IconButton(
                                    icon: const Icon(Icons.picture_in_picture, color: Colors.white),
                                    onPressed: () {},
                                  ),
                                  
                                  // Fullscreen
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // SponsorBlock skip toast
                  Positioned(
                    bottom: 80,
                    left: 16,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.sbSponsor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.skip_next, size: 16, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Sponsor skipped ✓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Video info
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        video?.title ?? 'Loading...',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      
                      // Views and date
                      Text(
                        '${video?.formattedViewCount ?? '0'} views • ${video?.publishedAt ?? ''}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      
                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionButton(Icons.thumb_up_outlined, 'Like'),
                          _buildActionButton(Icons.thumb_down_outlined, 'Dislike'),
                          _buildActionButton(Icons.share, 'Share'),
                          _buildActionButton(Icons.playlist_add, 'Save'),
                          _buildActionButton(Icons.download, 'Download'),
                        ],
                      ),
                      const Divider(height: 32, color: AppTheme.surfaceLight),
                      
                      // Channel info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.surfaceLight,
                            child: Text(
                              (video?.channelName ?? 'C')[0].toUpperCase(),
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video?.channelName ?? 'Channel',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Subscribe'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // SponsorBlock toggle
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.skip_next, color: AppTheme.sbSponsor),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SponsorBlock', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                                  Text('Skip sponsored segments automatically', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isSponsorBlockEnabled,
                              onChanged: (val) => setState(() => _isSponsorBlockEnabled = val),
                              activeColor: AppTheme.sbSponsor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Related videos
                      if (provider.relatedVideos.isNotEmpty) ...[
                        const Text(
                          'Related Videos',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...provider.relatedVideos.take(10).map((v) => _buildRelatedVideo(v)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.textSecondary),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildRelatedVideo(dynamic video) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 160,
              height: 90,
              color: AppTheme.surfaceLight,
              child: Stack(
                children: [
                  Center(
                    child: video.thumbnailUrl.isNotEmpty
                        ? Image.network(video.thumbnailUrl, fit: BoxFit.cover, width: 160, height: 90)
                        : const Icon(Icons.play_circle_outline, color: AppTheme.textMuted, size: 40),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.formattedDuration,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${video.channelName} • ${video.formattedViewCount} views',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Playback Speed', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0].map((speed) {
            return ListTile(
              title: Text('${speed}x', style: const TextStyle(color: AppTheme.textPrimary)),
              trailing: _playbackSpeed == speed ? const Icon(Icons.check, color: AppTheme.primary) : null,
              onTap: () {
                setState(() {
                  _playbackSpeed = speed;
                  _controller?.setPlaybackSpeed(speed);
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showQualityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Select Quality', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Auto', '1080p', '720p', '480p', '360p', 'Audio Only'].map((quality) {
            return ListTile(
              title: Text(quality, style: const TextStyle(color: AppTheme.textPrimary)),
              trailing: _selectedQuality == quality ? const Icon(Icons.check, color: AppTheme.primary) : null,
              onTap: () {
                setState(() => _selectedQuality = quality);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
