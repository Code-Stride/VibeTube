import 'dart:convert';
import 'package:http/http.dart' as http;

class InnerTubeClient {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  
  static const Map<String, dynamic> _context = {
    "client": {
      "hl": "en",
      "gl": "US",
      "clientName": "WEB",
      "clientVersion": "2.20231219.04.00",
      "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
  };

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  // Get trending videos
  Future<List<Video>> getTrending({String region = 'US'}) async {
    final response = await _makeRequest('browse', {
      'browseId': 'FEtrending',
      'context': {
        ..._context,
        'client': {
          ..._context['client'],
          'gl': region,
        }
      }
    });
    
    return _parseTrendingResponse(response);
  }

  // Search videos
  Future<SearchResult> search(String query, {String? continuation}) async {
    final body = {
      'query': query,
      'context': _context,
      'params': 'EgIQAQ%3D%3D', // Videos only
    };
    
    if (continuation != null) {
      body['continuation'] = continuation;
    }
    
    final response = await _makeRequest('search', body);
    return _parseSearchResponse(response);
  }

  // Get video details
  Future<VideoDetails> getVideoDetails(String videoId) async {
    final response = await _makeRequest('player', {
      'videoId': videoId,
      'context': {
        ..._context,
        'client': {
          ..._context['client'],
          'clientName': 'ANDROID',
          'clientVersion': '19.09.37',
          'androidSdkVersion': 30,
        }
      },
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
        }
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    });
    
    return _parseVideoDetails(response);
  }

  // Get video comments
  Future<List<Comment>> getComments(String videoId, {String? continuation}) async {
    final body = {
      'videoId': videoId,
      'context': _context,
      'sortNewestFirst': false,
    };
    
    if (continuation != null) {
      body['continuation'] = continuation;
    }
    
    final response = await _makeRequest('next', {
      'videoId': videoId,
      'context': _context,
    });
    
    return _parseCommentsResponse(response);
  }

  // Get related videos
  Future<List<Video>> getRelatedVideos(String videoId) async {
    final response = await _makeRequest('next', {
      'videoId': videoId,
      'context': _context,
    });
    
    return _parseRelatedVideosResponse(response);
  }

  // Get channel videos
  Future<List<Video>> getChannelVideos(String channelId) async {
    final response = await _makeRequest('browse', {
      'browseId': channelId,
      'context': _context,
    });
    
    return _parseChannelResponse(response);
  }

  // Get home feed
  Future<List<Video>> getHomeFeed() async {
    final response = await _makeRequest('browse', {
      'browseId': 'FEwhat_to_watch',
      'context': _context,
    });
    
    return _parseHomeFeedResponse(response);
  }

  Future<Map<String, dynamic>> _makeRequest(String endpoint, Map<String, dynamic> body) async {
    final url = '$_baseUrl/$endpoint?key=$_apiKey';
    
    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('InnerTube API error: ${response.statusCode}');
    }
  }

  List<Video> _parseTrendingResponse(Map<String, dynamic> response) {
    final List<Video> videos = [];
    
    try {
      final tabs = response['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
      if (tabs != null) {
        for (var tab in tabs) {
          final content = tab['tabRenderer']?['content'];
          if (content != null) {
            final items = content['richGridRenderer']?['contents'];
            if (items != null) {
              for (var item in items) {
                final video = _extractVideoFromRichItem(item);
                if (video != null) videos.add(video);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing trending: $e');
    }
    
    return videos;
  }

  SearchResult _parseSearchResponse(Map<String, dynamic> response) {
    final List<Video> videos = [];
    String? continuation;
    
    try {
      final contents = response['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents'];
      if (contents != null) {
        for (var section in contents) {
          final items = section['itemSectionRenderer']?['contents'];
          if (items != null) {
            for (var item in items) {
              final video = _extractVideoFromItem(item);
              if (video != null) videos.add(video);
            }
          }
          
          // Get continuation token
          final continuationItems = section['continuationItemRenderer'];
          if (continuationItems != null) {
            continuation = continuationItems['continuationEndpoint']?['continuationCommand']?['token'];
          }
        }
      }
    } catch (e) {
      print('Error parsing search: $e');
    }
    
    return SearchResult(videos: videos, continuation: continuation);
  }

  VideoDetails _parseVideoDetails(Map<String, dynamic> response) {
    try {
      final videoDetails = response['videoDetails'];
      final streamingData = response['streamingData'];
      final formats = streamingData?['formats'] ?? [];
      final adaptiveFormats = streamingData?['adaptiveFormats'] ?? [];
      
      return VideoDetails(
        id: videoDetails?['videoId'] ?? '',
        title: videoDetails?['title'] ?? '',
        description: videoDetails?['shortDescription'] ?? '',
        channelName: videoDetails?['author'] ?? '',
        channelId: videoDetails?['channelId'] ?? '',
        viewCount: int.tryParse(videoDetails?['viewCount'] ?? '0') ?? 0,
        duration: _parseDuration(videoDetails?['lengthSeconds'] ?? '0'),
        thumbnailUrl: videoDetails?['thumbnail']?['thumbnails']?.last?['url'] ?? '',
        formats: _parseFormats([...formats, ...adaptiveFormats]),
      );
    } catch (e) {
      throw Exception('Failed to parse video details: $e');
    }
  }

  List<Video> _parseRelatedVideosResponse(Map<String, dynamic> response) {
    final List<Video> videos = [];
    
    try {
      final results = response['contents']?['twoColumnWatchNextResults']?['secondaryResults']?['secondaryResults']?['results'];
      if (results != null) {
        for (var item in results) {
          final compactVideo = item['compactVideoRenderer'];
          if (compactVideo != null) {
            videos.add(_extractVideoFromCompact(compactVideo));
          }
        }
      }
    } catch (e) {
      print('Error parsing related videos: $e');
    }
    
    return videos;
  }

  List<Comment> _parseCommentsResponse(Map<String, dynamic> response) {
    final List<Comment> comments = [];
    
    try {
      final results = response['contents']?['twoColumnWatchNextResults']?['results']?['results']?['contents'];
      if (results != null) {
        for (var item in results) {
          final section = item['itemSectionRenderer'];
          if (section != null) {
            final contents = section['contents'];
            if (contents != null) {
              for (var content in contents) {
                final commentThread = content['commentThreadRenderer'];
                if (commentThread != null) {
                  comments.add(_extractComment(commentThread));
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing comments: $e');
    }
    
    return comments;
  }

  List<Video> _parseChannelResponse(Map<String, dynamic> response) {
    final List<Video> videos = [];
    
    try {
      final tabs = response['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
      if (tabs != null) {
        for (var tab in tabs) {
          final content = tab['tabRenderer']?['content'];
          if (content != null) {
            final items = content['sectionListRenderer']?['contents'];
            if (items != null) {
              for (var section in items) {
                final shelf = section['shelfRenderer'];
                if (shelf != null) {
                  final gridItems = shelf['content']?['gridRenderer']?['items'];
                  if (gridItems != null) {
                    for (var gridItem in gridItems) {
                      final video = _extractVideoFromGridItem(gridItem);
                      if (video != null) videos.add(video);
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing channel: $e');
    }
    
    return videos;
  }

  List<Video> _parseHomeFeedResponse(Map<String, dynamic> response) {
    final List<Video> videos = [];
    
    try {
      final tabs = response['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
      if (tabs != null) {
        for (var tab in tabs) {
          final content = tab['tabRenderer']?['content'];
          if (content != null) {
            final items = content['richGridRenderer']?['contents'];
            if (items != null) {
              for (var item in items) {
                final video = _extractVideoFromRichItem(item);
                if (video != null) videos.add(video);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing home feed: $e');
    }
    
    return videos;
  }

  Video? _extractVideoFromRichItem(Map<String, dynamic> item) {
    try {
      final videoRenderer = item['richItemRenderer']?['content']?['videoRenderer'];
      if (videoRenderer != null) {
        return _extractVideo(videoRenderer);
      }
    } catch (e) {}
    return null;
  }

  Video? _extractVideoFromItem(Map<String, dynamic> item) {
    try {
      final videoRenderer = item['videoRenderer'];
      if (videoRenderer != null) {
        return _extractVideo(videoRenderer);
      }
    } catch (e) {}
    return null;
  }

  Video? _extractVideoFromGridItem(Map<String, dynamic> item) {
    try {
      final videoRenderer = item['gridVideoRenderer'];
      if (videoRenderer != null) {
        return _extractVideo(videoRenderer);
      }
    } catch (e) {}
    return null;
  }

  Video _extractVideo(Map<String, dynamic> renderer) {
    final thumbnails = renderer['thumbnail']?['thumbnails'] ?? [];
    final thumbnailUrl = thumbnails.isNotEmpty ? thumbnails.last['url'] : '';
    
    return Video(
      id: renderer['videoId'] ?? '',
      title: _getText(renderer['title']),
      thumbnailUrl: thumbnailUrl.startsWith('//') ? 'https:$thumbnailUrl' : thumbnailUrl,
      channelName: _getText(renderer['ownerText']),
      channelId: renderer['ownerText']?['runs']?.first?['navigationEndpoint']?['browseEndpoint']?['browseId'] ?? '',
      viewCount: _parseViewCount(_getText(renderer['viewCountText'])),
      duration: _parseDurationText(_getText(renderer['lengthText'])),
      publishedAt: _getText(renderer['publishedTimeText']),
    );
  }

  Video _extractVideoFromCompact(Map<String, dynamic> renderer) {
    final thumbnails = renderer['thumbnail']?['thumbnails'] ?? [];
    final thumbnailUrl = thumbnails.isNotEmpty ? thumbnails.last['url'] : '';
    
    return Video(
      id: renderer['videoId'] ?? '',
      title: _getText(renderer['title']),
      thumbnailUrl: thumbnailUrl.startsWith('//') ? 'https:$thumbnailUrl' : thumbnailUrl,
      channelName: _getText(renderer['shortBylineText']),
      viewCount: _parseViewCount(_getText(renderer['viewCountText'])),
      duration: _parseDurationText(_getText(renderer['lengthText'])),
      publishedAt: _getText(renderer['publishedTimeText']),
    );
  }

  Comment _extractComment(Map<String, dynamic> commentThread) {
    final comment = commentThread['commentRenderer'];
    
    return Comment(
      id: comment?['commentId'] ?? '',
      author: _getText(comment?['authorText']),
      authorAvatar: comment?['authorThumbnail']?['thumbnails']?.last?['url'] ?? '',
      text: _getText(comment?['contentText']),
      likeCount: _parseViewCount(_getText(comment?['voteCount'])),
      publishedAt: _getText(comment?['publishedTimeText']),
    );
  }

  String _getText(dynamic textObj) {
    if (textObj == null) return '';
    if (textObj is String) return textObj;
    
    // Handle simpleText
    if (textObj['simpleText'] != null) {
      return textObj['simpleText'];
    }
    
    // Handle runs
    if (textObj['runs'] != null) {
      return textObj['runs'].map((r) => r['text'] ?? '').join('');
    }
    
    return '';
  }

  int _parseViewCount(String text) {
    if (text.isEmpty) return 0;
    text = text.replaceAll(RegExp(r'[^\dKMBkmb.]'), '');
    
    if (text.contains('K') || text.contains('k')) {
      return (double.tryParse(text.replaceAll(RegExp(r'[Kk]'), '')) ?? 0 * 1000).toInt();
    }
    if (text.contains('M') || text.contains('m')) {
      return (double.tryParse(text.replaceAll(RegExp(r'[Mm]'), '')) ?? 0 * 1000000).toInt();
    }
    if (text.contains('B') || text.contains('b')) {
      return (double.tryParse(text.replaceAll(RegExp(r'[Bb]'), '')) ?? 0 * 1000000000).toInt();
    }
    
    return int.tryParse(text) ?? 0;
  }

  Duration _parseDuration(String seconds) {
    return Duration(seconds: int.tryParse(seconds) ?? 0);
  }

  Duration _parseDurationText(String text) {
    if (text.isEmpty) return Duration.zero;
    
    final parts = text.split(':').reversed.toList();
    int seconds = 0;
    
    if (parts.isNotEmpty) seconds += int.tryParse(parts[0]) ?? 0;
    if (parts.length > 1) seconds += (int.tryParse(parts[1]) ?? 0) * 60;
    if (parts.length > 2) seconds += (int.tryParse(parts[2]) ?? 0) * 3600;
    
    return Duration(seconds: seconds);
  }

  List<VideoFormat> _parseFormats(List<dynamic> formats) {
    return formats.map((f) {
      final url = f['url'];
      final quality = f['qualityLabel'] ?? f['quality'] ?? 'Unknown';
      final mimeType = f['mimeType'] ?? '';
      final width = f['width'] ?? 0;
      final height = f['height'] ?? 0;
      final bitrate = f['bitrate'] ?? 0;
      
      return VideoFormat(
        url: url ?? '',
        quality: quality,
        mimeType: mimeType,
        width: width,
        height: height,
        bitrate: bitrate,
        isVideoOnly: mimeType.contains('video') && !mimeType.contains('audio'),
        isAudioOnly: mimeType.contains('audio'),
      );
    }).toList();
  }
}

// Models
class Video {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String channelName;
  final String channelId;
  final int viewCount;
  final Duration duration;
  final String publishedAt;

  Video({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    this.channelName = '',
    this.channelId = '',
    this.viewCount = 0,
    this.duration = Duration.zero,
    this.publishedAt = '',
  });

  String get formattedViewCount {
    if (viewCount >= 1000000000) return '${(viewCount / 1000000000).toStringAsFixed(1)}B';
    if (viewCount >= 1000000) return '${(viewCount / 1000000).toStringAsFixed(1)}M';
    if (viewCount >= 1000) return '${(viewCount / 1000).toStringAsFixed(1)}K';
    return viewCount.toString();
  }

  String get formattedDuration {
    if (duration == Duration.zero) return '0:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class VideoDetails extends Video {
  final String description;
  final List<VideoFormat> formats;

  VideoDetails({
    required String id,
    required String title,
    this.description = '',
    String channelName = '',
    String channelId = '',
    int viewCount = 0,
    Duration duration = Duration.zero,
    String thumbnailUrl = '',
    this.formats = const [],
  }) : super(
    id: id,
    title: title,
    thumbnailUrl: thumbnailUrl,
    channelName: channelName,
    channelId: channelId,
    viewCount: viewCount,
    duration: duration,
  );
}

class VideoFormat {
  final String url;
  final String quality;
  final String mimeType;
  final int width;
  final int height;
  final int bitrate;
  final bool isVideoOnly;
  final bool isAudioOnly;

  VideoFormat({
    required this.url,
    required this.quality,
    this.mimeType = '',
    this.width = 0,
    this.height = 0,
    this.bitrate = 0,
    this.isVideoOnly = false,
    this.isAudioOnly = false,
  });
}

class Comment {
  final String id;
  final String author;
  final String authorAvatar;
  final String text;
  final int likeCount;
  final String publishedAt;

  Comment({
    required this.id,
    required this.author,
    this.authorAvatar = '',
    required this.text,
    this.likeCount = 0,
    this.publishedAt = '',
  });
}

class SearchResult {
  final List<Video> videos;
  final String? continuation;

  SearchResult({required this.videos, this.continuation});
}
