import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video.dart';

/// YouTube InnerTube client.
/// ANDROID client returns plain progressive MP4 URLs (no cipher) — most reliable for mobile players.
class InnerTubeClient {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';

  /// Proven working clients (ordered by reliability for plain URLs).
  static const List<Map<String, dynamic>> _playerClients = [
    {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
      'androidSdkVersion': 34,
      'osName': 'Android',
      'osVersion': '14',
      'hl': 'en',
      'gl': 'IN',
      '_ua': 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
    },
    {
      'clientName': 'IOS',
      'clientVersion': '20.10.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
      'hl': 'en',
      'gl': 'US',
      '_ua':
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    },
    {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.60.19',
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'androidSdkVersion': 32,
      'hl': 'en',
      'gl': 'US',
      '_ua':
          'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L) gzip',
    },
  ];

  static const Map<String, dynamic> _webClient = {
    'hl': 'en',
    'gl': 'IN',
    'clientName': 'WEB',
    'clientVersion': '2.20250312.00.00',
    'userAgent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  final http.Client _http = http.Client();

  Map<String, String> _headers(String? ua) => {
        'Content-Type': 'application/json',
        'User-Agent': ua ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
      };

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? userAgent,
  }) async {
    final uri = Uri.parse('$_baseUrl/$endpoint?prettyPrint=false');
    final res = await _http
        .post(
          uri,
          headers: _headers(userAgent),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 18));
    if (res.statusCode != 200) {
      throw Exception('InnerTube $endpoint HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------- Browse / Search ----------------

  Future<List<Video>> getTrending({String region = 'IN'}) async {
    try {
      final response = await _post('browse', {
        'browseId': 'FEtrending',
        'context': {
          'client': {..._webClient, 'gl': region},
        },
      }, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) return videos;
    } catch (_) {}
    return getHomeFeed(region: region);
  }

  Future<List<Video>> getHomeFeed({String region = 'IN'}) async {
    final response = await _post('browse', {
      'browseId': 'FEwhat_to_watch',
      'context': {
        'client': {..._webClient, 'gl': region},
      },
    }, userAgent: _webClient['userAgent'] as String);
    return _parseVideosDeep(response);
  }

  Future<SearchResult> search(String query, {String? continuation}) async {
    final body = <String, dynamic>{
      'query': query,
      'context': {'client': _webClient},
      'params': 'EgIQAQ%3D%3D',
    };
    if (continuation != null) body['continuation'] = continuation;
    final response = await _post(
      'search',
      body,
      userAgent: _webClient['userAgent'] as String,
    );
    final videos = _parseVideosDeep(response);
    return SearchResult(videos: videos, continuation: null);
  }

  /// Fetch playable details.
  /// Merges ANDROID progressive (instant/reliable) + IOS HLS (720p–4K adaptive).
  Future<VideoDetails> getVideoDetails(String videoId) async {
    Object? lastError;
    VideoDetails? androidDetails;
    VideoDetails? iosDetails;
    VideoDetails? anyOk;

    for (final raw in _playerClients) {
      final cfg = Map<String, dynamic>.from(raw);
      final ua = cfg.remove('_ua') as String?;
      final name = cfg['clientName']?.toString() ?? '';
      try {
        final details = await _fetchPlayer(videoId, cfg, ua);
        anyOk ??= details;
        if (name == 'ANDROID' || name == 'ANDROID_VR') {
          if (details.bestMuxedUrl != null) {
            androidDetails ??= details;
          } else {
            anyOk = details;
          }
        } else if (name == 'IOS') {
          if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
            iosDetails ??= details;
          }
        } else {
          if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
            iosDetails ??= details;
          }
          if (details.bestMuxedUrl != null) {
            androidDetails ??= details;
          }
        }
        // Stop early once we have both stream types
        if (androidDetails != null && iosDetails != null) break;
      } catch (e) {
        lastError = e;
      }
    }

    VideoDetails? base = iosDetails ?? androidDetails ?? anyOk;
    if (base == null) {
      throw Exception('No playable stream found. $lastError');
    }

    // Merge formats from android + hls from ios
    final formats = <VideoFormat>[
      ...?androidDetails?.formats,
      ...?iosDetails?.formats,
    ];
    // Dedupe by url
    final seen = <String>{};
    final mergedFormats = <VideoFormat>[];
    for (final f in formats) {
      if (f.url.isNotEmpty && seen.add(f.url)) mergedFormats.add(f);
    }

    return VideoDetails(
      id: base.id,
      title: (iosDetails?.title.isNotEmpty == true)
          ? iosDetails!.title
          : (androidDetails?.title ?? base.title),
      description: base.description.isNotEmpty
          ? base.description
          : (androidDetails?.description ?? iosDetails?.description ?? ''),
      channelName: base.channelName.isNotEmpty
          ? base.channelName
          : (androidDetails?.channelName ?? ''),
      channelId: base.channelId.isNotEmpty
          ? base.channelId
          : (androidDetails?.channelId ?? ''),
      viewCount: base.viewCount > 0
          ? base.viewCount
          : (androidDetails?.viewCount ?? iosDetails?.viewCount ?? 0),
      duration: base.duration != Duration.zero
          ? base.duration
          : (androidDetails?.duration ?? Duration.zero),
      thumbnailUrl: base.thumbnailUrl.isNotEmpty
          ? base.thumbnailUrl
          : (androidDetails?.thumbnailUrl ?? ''),
      publishedAt: base.publishedAt,
      formats: mergedFormats.isNotEmpty ? mergedFormats : base.formats,
      hlsUrl: iosDetails?.hlsUrl ?? base.hlsUrl,
      dashUrl: base.dashUrl ?? androidDetails?.dashUrl,
      likeCount: base.likeCount,
      isLive: base.isLive || (androidDetails?.isLive ?? false),
    );
  }

  Future<VideoDetails> _fetchPlayer(
    String videoId,
    Map<String, dynamic> client,
    String? ua,
  ) async {
    final body = {
      'videoId': videoId,
      'context': {
        'client': client,
      },
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
        }
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    };

    final response = await _post('player', body, userAgent: ua);
    final status = response['playabilityStatus']?['status']?.toString();
    if (status != null && status != 'OK') {
      final reason =
          response['playabilityStatus']?['reason']?.toString() ?? status;
      throw Exception('Unplayable ($status): $reason');
    }
    return _parseVideoDetails(response, videoId);
  }

  Future<List<Video>> getRelatedVideos(String videoId) async {
    try {
      final response = await _post('next', {
        'videoId': videoId,
        'context': {'client': _webClient},
      }, userAgent: _webClient['userAgent'] as String);
      return _parseVideosDeep(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<Comment>> getComments(String videoId) async {
    try {
      final response = await _post('next', {
        'videoId': videoId,
        'context': {'client': _webClient},
      }, userAgent: _webClient['userAgent'] as String);
      return _parseCommentsDeep(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<SponsorSegment>> getSponsorSegments(String videoId) async {
    try {
      final uri = Uri.parse(
        'https://sponsor.ajay.app/api/skipSegments?videoID=$videoId'
        '&categories=%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%2C%22filler%22%5D',
      );
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as List<dynamic>;
      return data.map((s) {
        final seg = s['segment'] as List<dynamic>;
        return SponsorSegment(
          start: (seg[0] as num).toDouble(),
          end: (seg[1] as num).toDouble(),
          category: s['category']?.toString() ?? 'sponsor',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<int?> getDislikeCount(String videoId) async {
    try {
      final uri = Uri.parse(
        'https://returnyoutubedislikeapi.com/votes?videoId=$videoId',
      );
      final res = await _http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'VibeTube/1.2',
      }).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['dislikes'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  // ---------------- Parsers ----------------

  VideoDetails _parseVideoDetails(
      Map<String, dynamic> response, String videoId) {
    final vd = response['videoDetails'] as Map<String, dynamic>? ?? {};
    final sd = response['streamingData'] as Map<String, dynamic>? ?? {};
    final micro = response['microformat']?['playerMicroformatRenderer']
        as Map<String, dynamic>?;

    final formats = <dynamic>[
      ...(sd['formats'] as List<dynamic>? ?? const []),
      ...(sd['adaptiveFormats'] as List<dynamic>? ?? const []),
    ];

    final thumbs = vd['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
    var thumb = thumbs.isNotEmpty
        ? (thumbs.last['url']?.toString() ?? '')
        : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    if (thumb.startsWith('//')) thumb = 'https:$thumb';

    return VideoDetails(
      id: vd['videoId']?.toString() ?? videoId,
      title: vd['title']?.toString() ?? '',
      description: vd['shortDescription']?.toString() ?? '',
      channelName: vd['author']?.toString() ?? '',
      channelId: vd['channelId']?.toString() ?? '',
      viewCount: int.tryParse(vd['viewCount']?.toString() ?? '0') ?? 0,
      duration: Duration(
          seconds: int.tryParse(vd['lengthSeconds']?.toString() ?? '0') ?? 0),
      thumbnailUrl: thumb,
      publishedAt: micro?['publishDate']?.toString() ?? '',
      formats: _parseFormats(formats),
      hlsUrl: sd['hlsManifestUrl']?.toString(),
      dashUrl: sd['dashManifestUrl']?.toString(),
      isLive: vd['isLiveContent'] == true || vd['isLive'] == true,
    );
  }

  List<VideoFormat> _parseFormats(List<dynamic> formats) {
    final out = <VideoFormat>[];
    for (final f in formats) {
      if (f is! Map) continue;
      // Only plain URLs — skip ciphered streams
      final url = f['url']?.toString() ?? '';
      if (url.isEmpty) continue;

      final mime = (f['mimeType']?.toString() ?? '').toLowerCase();
      final hasVideo = mime.contains('video');
      final hasAudioCodec = mime.contains('mp4a') ||
          mime.contains('opus') ||
          mime.contains('mp4a.40') ||
          f['audioQuality'] != null;
      final isAudioOnly = mime.startsWith('audio/');
      // Progressive muxed: video/* with audio codec listed
      final isMuxed = hasVideo && hasAudioCodec && !isAudioOnly;
      final isVideoOnly = hasVideo && !isMuxed && !isAudioOnly;

      out.add(VideoFormat(
        url: url,
        quality: f['qualityLabel']?.toString() ??
            f['quality']?.toString() ??
            'Unknown',
        mimeType: f['mimeType']?.toString() ?? '',
        width: f['width'] as int? ?? 0,
        height: f['height'] as int? ?? 0,
        bitrate: f['bitrate'] as int? ?? 0,
        itag: f['itag'] as int? ?? 0,
        isVideoOnly: isVideoOnly,
        isAudioOnly: isAudioOnly,
        hasAudio: isAudioOnly || isMuxed || f['audioQuality'] != null,
        hasVideo: hasVideo,
      ));
    }
    return out;
  }

  List<Video> _parseVideosDeep(Map<String, dynamic> response) {
    final videos = <Video>[];
    void walk(dynamic node) {
      if (node is Map) {
        for (final key in [
          'videoRenderer',
          'compactVideoRenderer',
          'gridVideoRenderer',
          'playlistVideoRenderer',
        ]) {
          if (node[key] is Map) {
            final v = _extractVideo(Map<String, dynamic>.from(node[key] as Map));
            if (v != null) videos.add(v);
          }
        }
        if (node['richItemRenderer'] is Map) {
          walk(node['richItemRenderer']['content']);
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final i in node) {
          walk(i);
        }
      }
    }

    walk(response);
    final seen = <String>{};
    return videos.where((v) => v.id.isNotEmpty && seen.add(v.id)).toList();
  }

  List<Comment> _parseCommentsDeep(Map<String, dynamic> response) {
    final comments = <Comment>[];
    void walk(dynamic node) {
      if (node is Map) {
        Map? cr = node['commentRenderer'] as Map?;
        cr ??= node['commentThreadRenderer']?['comment']?['commentRenderer']
            as Map?;
        if (cr != null) {
          comments.add(Comment(
            id: cr['commentId']?.toString() ?? '',
            author: _text(cr['authorText']),
            authorAvatar: (cr['authorThumbnail']?['thumbnails'] as List?)
                    ?.last?['url']
                    ?.toString() ??
                '',
            text: _text(cr['contentText']),
            likeCount: _parseCount(_text(cr['voteCount'])),
            publishedAt: _text(cr['publishedTimeText']),
          ));
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final i in node) {
          walk(i);
        }
      }
    }

    walk(response);
    return comments;
  }

  Video? _extractVideo(Map<String, dynamic> r) {
    final id = r['videoId']?.toString();
    if (id == null || id.isEmpty) return null;
    final thumbs = r['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
    var thumb = thumbs.isNotEmpty ? thumbs.last['url']?.toString() ?? '' : '';
    if (thumb.startsWith('//')) thumb = 'https:$thumb';
    if (thumb.isEmpty) thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

    String channelName = _text(r['ownerText']);
    if (channelName.isEmpty) channelName = _text(r['shortBylineText']);
    if (channelName.isEmpty) channelName = _text(r['longBylineText']);

    String channelId = '';
    try {
      channelId = r['ownerText']?['runs']?[0]?['navigationEndpoint']
                  ?['browseEndpoint']?['browseId']
              ?.toString() ??
          r['shortBylineText']?['runs']?[0]?['navigationEndpoint']
                  ?['browseEndpoint']?['browseId']
              ?.toString() ??
          '';
    } catch (_) {}

    String avatar = '';
    try {
      final ch = r['channelThumbnailSupportedRenderers']
              ?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails']
          as List?;
      if (ch != null && ch.isNotEmpty) {
        avatar = ch.last['url']?.toString() ?? '';
      }
    } catch (_) {}

    final viewsText = _text(r['viewCountText']).isNotEmpty
        ? _text(r['viewCountText'])
        : _text(r['shortViewCountText']);

    return Video(
      id: id,
      title: _text(r['title']),
      thumbnailUrl: thumb,
      channelName: channelName,
      channelId: channelId,
      channelAvatar: avatar,
      viewCount: _parseCount(viewsText),
      duration: _parseDurationText(_text(r['lengthText'])),
      publishedAt: _text(r['publishedTimeText']),
      description: _text(r['descriptionSnippet']),
    );
  }

  String _text(dynamic o) {
    if (o == null) return '';
    if (o is String) return o;
    if (o is Map) {
      if (o['simpleText'] != null) return o['simpleText'].toString();
      if (o['runs'] is List) {
        return (o['runs'] as List).map((r) => r['text'] ?? '').join();
      }
    }
    return '';
  }

  int _parseCount(String text) {
    if (text.isEmpty) return 0;
    final cleaned = text.replaceAll(',', '').trim();
    final m = RegExp(r'([\d.]+)\s*([KMBTkmbt])?').firstMatch(cleaned);
    if (m == null) {
      return int.tryParse(cleaned.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    final n = double.tryParse(m.group(1)!) ?? 0;
    switch ((m.group(2) ?? '').toUpperCase()) {
      case 'K':
        return (n * 1e3).round();
      case 'M':
        return (n * 1e6).round();
      case 'B':
        return (n * 1e9).round();
      default:
        return n.round();
    }
  }

  Duration _parseDurationText(String text) {
    if (text.isEmpty) return Duration.zero;
    final parts = text.split(':');
    try {
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      }
      if (parts.length == 2) {
        return Duration(
            minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      }
    } catch (_) {}
    return Duration.zero;
  }

  void dispose() => _http.close();
}
