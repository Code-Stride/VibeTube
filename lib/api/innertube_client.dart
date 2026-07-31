import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video.dart';
import '../services/hls_parser.dart';

/// YouTube InnerTube client.
/// ANDROID client returns plain progressive MP4 URLs (no cipher) — most reliable for mobile players.
class InnerTubeClient {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';

  /// Proven working clients (ordered by reliability for plain URLs).
  static const List<Map<String, dynamic>> _playerClients = [
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
      '_clientNameId': '5',
    },
    {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
      'androidSdkVersion': 34,
      'osName': 'Android',
      'osVersion': '14',
      'hl': 'en',
      'gl': 'IN',
      '_ua': 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      '_clientNameId': '3',
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

  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? userAgent,
    Map<String, String>? extraHeaders,
    String? clientNameId,
    String? clientVersion,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/$endpoint?prettyPrint=false&key=$_apiKey',
    );
    final headers = {
      ..._headers(userAgent),
      'X-YouTube-Client-Name': clientNameId ?? '1',
      'X-YouTube-Client-Version':
          clientVersion ?? (_webClient['clientVersion'] as String?) ?? '2.20250312.00.00',
      if (extraHeaders != null) ...extraHeaders,
    };
    final res = await _http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 18));
    if (res.statusCode != 200) {
      throw Exception('InnerTube $endpoint HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------- Browse / Search ----------------

  /// "All" feed. YouTube browse/home often returns empty without cookies,
  /// so we build a rich feed from multiple working search queries + optional browse.
  Future<List<Video>> getTrending({String region = 'IN'}) async {
    final client = {..._webClient, 'gl': region};

    // 1) Try classic trending browse (may 400 / empty)
    try {
      final response = await _post('browse', {
        'browseId': 'FEtrending',
        'context': {'client': client},
      }, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.length >= 8) return videos;
    } catch (_) {}

    // 2) Try home browse
    try {
      final home = await getHomeFeed(region: region);
      if (home.length >= 8) return home;
    } catch (_) {}

    // 3) Reliable multi-search feed (always works)
    return _buildDiscoverFeed(region: region);
  }

  Future<List<Video>> getHomeFeed({String region = 'IN'}) async {
    final client = {..._webClient, 'gl': region};
    try {
      final response = await _post('browse', {
        'browseId': 'FEwhat_to_watch',
        'context': {'client': client},
      }, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) return videos;
    } catch (_) {}
    return _buildDiscoverFeed(region: region);
  }

  /// Category chip feed.
  /// InnerTube search filter params (raw base64, NOT URL-encoded).
  static const String kFilterVideos = 'EgIQAQ==';
  static const String kFilterShorts = 'EgIYAQ==';
  static const String kFilterLive = 'EgJAAQ==';

  Future<List<Video>> getCategoryFeed(String category, {String region = 'IN'}) async {
    final c = category.trim().toLowerCase();
    final isIn = region.toUpperCase() == 'IN';

    if (c == 'shorts') {
      final q = isIn ? 'shorts india' : 'shorts';
      var result = await search(q, params: kFilterShorts);
      if (result.videos.isEmpty) {
        result = await search('#shorts', params: kFilterShorts);
      }
      if (result.videos.isEmpty) {
        result = await search('youtube shorts', params: kFilterShorts);
      }
      return result.videos;
    }

    if (c == 'live') {
      final q = isIn ? 'live news india' : 'live news';
      var result = await search(q, params: kFilterLive);
      if (result.videos.isEmpty) {
        result = await search('live', params: kFilterLive);
      }
      return result.videos;
    }

    final q = _categoryQuery(category, region);
    final result = await search(q, params: kFilterVideos);
    if (result.videos.isNotEmpty) return result.videos;
    final alt = await search(category, params: kFilterVideos);
    return alt.videos;
  }

  String _categoryQuery(String category, String region) {
    final c = category.trim().toLowerCase();
    final isIn = region.toUpperCase() == 'IN';
    switch (c) {
      case 'all':
        return isIn ? 'trending india' : 'trending';
      case 'music':
        return isIn ? 'bollywood songs' : 'music videos';
      case 'gaming':
        return isIn ? 'gaming india' : 'gaming';
      case 'news':
        return isIn ? 'news india today' : 'world news today';
      case 'sports':
        return isIn ? 'cricket highlights' : 'sports highlights';
      case 'movies':
        return isIn ? 'bollywood movie trailers' : 'movie trailers';
      case 'education':
        return isIn ? 'study with me india' : 'education';
      case 'technology':
        return isIn ? 'tech india' : 'technology';
      case 'comedy':
        return isIn ? 'indian comedy' : 'comedy';
      default:
        return category;
    }
  }

  Future<List<Video>> _buildDiscoverFeed({String region = 'IN'}) async {
    final isIn = region.toUpperCase() == 'IN';
    final queries = isIn
        ? <String>[
            'trending india',
            'bollywood songs',
            'cricket',
            'news india',
            'comedy india',
            'tech reviews',
            'youtube shorts india',
            'live news india',
            'viral videos india',
          ]
        : <String>[
            'trending',
            'music',
            'gaming',
            'news today',
            'sports',
            'comedy',
            'youtube shorts',
            'live',
            'viral',
          ];

    final seen = <String>{};
    final out = <Video>[];

    // Parallel batches of 4 for speed, with delay between batches to avoid rate limiting
    for (var i = 0; i < queries.length; i += 4) {
      if (i > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      final batch = queries.sublist(i, (i + 4).clamp(0, queries.length));
      final results = await Future.wait(
        batch.map((q) async {
          try {
            final r = await search(q);
            return r.videos;
          } catch (_) {
            return <Video>[];
          }
        }),
      );
      // Interleave so feed feels mixed, not one-topic blocks
      final lists = results.where((l) => l.isNotEmpty).toList();
      var idx = 0;
      var added = true;
      while (added) {
        added = false;
        for (final list in lists) {
          if (idx < list.length) {
            final v = list[idx];
            if (v.id.isNotEmpty && seen.add(v.id)) {
              out.add(v);
              added = true;
            }
          }
        }
        idx++;
      }
      if (out.length >= 60) break;
    }
    return out;
  }

  Future<SearchResult> search(String query, {String? continuation, String? params}) async {
    final client = Map<String, dynamic>.from(_webClient);
    final body = <String, dynamic>{
      'query': query,
      'context': {'client': client},
      'params': params ?? kFilterVideos,
    };
    if (continuation != null) body['continuation'] = continuation;

    // WEB search first
    try {
      final response = await _post(
        'search',
        body,
        userAgent: _webClient['userAgent'] as String,
      );
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) {
        return SearchResult(videos: videos, continuation: null);
      }
    } catch (_) {}

    // ANDROID search fallback (compactVideoRenderer)
    try {
      final androidClient = {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'androidSdkVersion': 34,
        'hl': client['hl'] ?? 'en',
        'gl': client['gl'] ?? 'IN',
      };
      final response = await _post(
        'search',
        {
          'query': query,
          'context': {'client': androidClient},
          'params': params ?? kFilterVideos,
        },
        userAgent:
            'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      );
      final videos = _parseVideosDeep(response);
      return SearchResult(videos: videos, continuation: null);
    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }

  /// Fetch playable details.
  /// Always merges IOS HLS (multi-quality) + ANDROID progressive (fallback).
  Future<VideoDetails> getVideoDetails(String videoId) async {
    Object? lastError;
    VideoDetails? androidDetails;
    VideoDetails? iosDetails;

    // Fetch IOS + ANDROID in parallel — never skip HLS for speed.
    final futures = <Future<void>>[];
    for (final raw in _playerClients) {
      final cfg = Map<String, dynamic>.from(raw);
      final ua = cfg.remove('_ua') as String?;
      final name = cfg['clientName']?.toString() ?? '';
      futures.add(() async {
        try {
          final details = await _fetchPlayer(videoId, cfg, ua);
          if (name == 'IOS') {
            if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
              iosDetails = details;
            }
          } else if (name == 'ANDROID' || name == 'ANDROID_VR') {
            androidDetails = details;
          }
        } catch (e) {
          lastError = e;
        }
      }());
    }
    await Future.wait(futures);

    final base = iosDetails ?? androidDetails;
    if (base == null) {
      throw Exception('No playable stream found. $lastError');
    }

    final formats = <VideoFormat>[
      ...?androidDetails?.formats,
      ...?iosDetails?.formats,
    ];
    final seen = <String>{};
    final mergedFormats = <VideoFormat>[];
    for (final f in formats) {
      if (f.url.isNotEmpty && seen.add(f.url)) mergedFormats.add(f);
    }

    final formatsFinal =
        mergedFormats.isNotEmpty ? mergedFormats : base.formats;
    // Live: ANDROID HLS is more reliable; VOD: prefer IOS multi-quality HLS
    String? hls;
    final liveGuess = (iosDetails?.isLive ?? false) ||
        (androidDetails?.isLive ?? false) ||
        (base.isLive);
    if (liveGuess) {
      hls = androidDetails?.hlsUrl ?? iosDetails?.hlsUrl ?? base.hlsUrl;
    } else {
      hls = iosDetails?.hlsUrl ?? androidDetails?.hlsUrl ?? base.hlsUrl;
    }

    // Progressive muxed by height
    final progressive = <int, String>{};
    for (final f in formatsFinal.where((f) => f.isMuxed && f.height > 0)) {
      progressive.putIfAbsent(f.height, () => f.url);
    }

    // Parse HLS master → per-quality locked playlists (critical for 720p+)
    var hlsVariants = <int, String>{};
    if (hls != null && hls.isNotEmpty) {
      final variants = await HlsParser.parseMaster(
        hls,
        headers: const {
          'User-Agent':
              'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          'Accept': '*/*',
        },
      );
      for (final v in variants) {
        // Keep best per height (parser already prefers avc1)
        hlsVariants[v.height] = v.url;
      }
    }

    // Also map standard ladder keys (720, 1080) from nearest actual heights
    // e.g. if we have 1280x720 only as 720
    final normalized = <int, String>{};
    for (final e in hlsVariants.entries) {
      final h = e.key;
      int bucket;
      if (h >= 2000) {
        bucket = 2160;
      } else if (h >= 1300) {
        bucket = 1440;
      } else if (h >= 900) {
        bucket = 1080;
      } else if (h >= 600) {
        bucket = 720;
      } else if (h >= 420) {
        bucket = 480;
      } else if (h >= 300) {
        bucket = 360;
      } else if (h >= 200) {
        bucket = 240;
      } else {
        bucket = 144;
      }
      // Prefer exact-ish higher score already in map; keep first avc-preferring
      normalized.putIfAbsent(bucket, () => e.value);
      normalized[h] = e.value; // keep exact too
    }
    hlsVariants = normalized;

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
      formats: formatsFinal,
      hlsUrl: hls,
      dashUrl: base.dashUrl ?? androidDetails?.dashUrl,
      likeCount: base.likeCount,
      isLive: liveGuess ||
          base.isLive ||
          (androidDetails?.isLive ?? false) ||
          (iosDetails?.isLive ?? false),
      isShort: base.isShort || (androidDetails?.isShort ?? false),
      hlsVariants: hlsVariants,
      progressiveByHeight: progressive,
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

    // Extract client-specific header info before sending
    final clientNameId = client.remove('_clientNameId') as String?;
    final clientVersion = client['clientVersion'] as String?;

    final response = await _post('player', body, userAgent: ua,
        clientNameId: clientNameId, clientVersion: clientVersion);
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
    } catch (e) {
      debugPrint('getRelatedVideos error for $videoId: $e');
      return [];
    }
  }

  Future<List<Comment>> getComments(String videoId) async {
    try {
      final response = await _post('next', {
        'videoId': videoId,
        'context': {'client': _webClient},
      }, userAgent: _webClient['userAgent'] as String);
      final comments = _parseCommentsDeep(response);
      return comments;
    } catch (e) {
      debugPrint('getComments error for $videoId: $e');
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
      isLive: vd['isLiveContent'] == true ||
          vd['isLive'] == true ||
          (vd['isUpcoming'] != true &&
              ((vd['lengthSeconds']?.toString() == '0') ||
                  (int.tryParse(vd['lengthSeconds']?.toString() ?? '-1') == 0)) &&
              (sd['hlsManifestUrl'] != null || sd['dashManifestUrl'] != null)),
      isShort: (int.tryParse(vd['lengthSeconds']?.toString() ?? '0') ?? 0) > 0 &&
          (int.tryParse(vd['lengthSeconds']?.toString() ?? '0') ?? 0) <= 60 &&
          (vd['title']?.toString().toLowerCase().contains('#shorts') == true ||
           vd['title']?.toString().toLowerCase().contains('#short') == true),
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
          'reelItemRenderer',
          'shortsLockupViewModel',
          'gridVideoRenderer',
        ]) {
          if (node[key] is Map) {
            final map = Map<String, dynamic>.from(node[key] as Map);
            Video? v;
            if (key == 'reelItemRenderer' || key == 'shortsLockupViewModel') {
              v = _extractShort(map, key);
            } else {
              v = _extractVideo(map);
            }
            if (v != null) videos.add(v);
          }
        }
        // lockupViewModel (newer YT UI) — try extract video id from entity
        if (node['lockupViewModel'] is Map) {
          final v = _extractLockup(Map<String, dynamic>.from(node['lockupViewModel'] as Map));
          if (v != null) videos.add(v);
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

  Video? _extractShort(Map<String, dynamic> r, String kind) {
    try {
      String id = '';
      String title = '';
      String thumb = '';
      String channel = '';

      if (kind == 'reelItemRenderer') {
        id = r['videoId']?.toString() ??
            r['navigationEndpoint']?['reelWatchEndpoint']?['videoId']?.toString() ??
            '';
        title = _text(r['headline']) ;
        if (title.isEmpty) title = _text(r['overlayMetadata']?['primaryText']);
        final th = r['thumbnail']?['thumbnails'] as List? ??
            r['thumbnails'] as List? ??
            const [];
        if (th.isNotEmpty) thumb = th.last['url']?.toString() ?? '';
        channel = _text(r['overlayMetadata']?['secondaryText']);
      } else {
        // shortsLockupViewModel
        id = r['onTap']?['innertubeCommand']?['reelWatchEndpoint']?['videoId']
                ?.toString() ??
            r['entityId']?.toString().replaceAll('shorts-shelf-item-', '') ??
            '';
        // entity id sometimes "shorts-shelf-item-VIDEOID"
        if (id.contains('-')) {
          final parts = id.split('-');
          if (parts.last.length == 11) id = parts.last;
        }
        title = _text(r['overlayMetadata']?['primaryText']) ;
        if (title.isEmpty) title = r['accessibilityText']?.toString() ?? '';
        final th = r['thumbnail']?['sources'] as List? ??
            r['thumbnailViewModel']?['image']?['sources'] as List? ??
            const [];
        if (th.isNotEmpty) thumb = th.last['url']?.toString() ?? '';
      }

      if (id.isEmpty || id.length < 10) return null;
      if (thumb.startsWith('//')) thumb = 'https:$thumb';
      if (thumb.isEmpty) thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

      return Video(
        id: id,
        title: title.isEmpty ? 'Short' : title,
        thumbnailUrl: thumb,
        channelName: channel,
        duration: const Duration(seconds: 30),
        isShort: true,
      );
    } catch (_) {
      return null;
    }
  }

  Video? _extractLockup(Map<String, dynamic> r) {
    try {
      // Try to find videoId from known fields first
      String id = r['contentId']?.toString() ?? '';
      if (id.isEmpty || id.length != 11) {
        // Walk nested structures properly instead of regex on toString()
        id = _findVideoIdDeep(r) ?? '';
      }
      if (id.length != 11) return null;
      String title = '';
      String channel = '';
      String thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
      // try metadata rows
      void scan(dynamic n) {
        if (n is Map) {
          if (n['text'] is Map) {
            final tx = _text(n['text']);
            if (title.isEmpty && tx.length > 3) title = tx;
          }
          for (final v in n.values) {
            scan(v);
          }
        } else if (n is List) {
          for (final i in n) {
            scan(i);
          }
        }
      }
      scan(r['metadata']);
      final blob = r.toString().toUpperCase();
      final live = blob.contains('LIVE') || blob.contains('BADGE_STYLE_TYPE_LIVE');
      return Video(
        id: id,
        title: title.isEmpty ? 'Video' : title,
        thumbnailUrl: thumb,
        channelName: channel,
        isLive: live,
      );
    } catch (_) {
      return null;
    }
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

    final lengthText = _text(r['lengthText']);
    final badges = r['badges'] as List? ?? const [];
    var isLive = false;
    for (final b in badges) {
      final label = b is Map
          ? '${_text(b['metadataBadgeRenderer']?['label'])} '
              '${b['metadataBadgeRenderer']?['style']?.toString() ?? ''}'
          : '';
      if (label.toUpperCase().contains('LIVE')) isLive = true;
    }
    if (r['thumbnailOverlays'] is List) {
      for (final o in r['thumbnailOverlays']) {
        final s = o.toString().toUpperCase();
        if (s.contains('LIVE')) isLive = true;
      }
    }
    // Shorts: only flag as short when there's a strong signal (navigation endpoint)
    var isShort = false;
    try {
      final nav = r['navigationEndpoint']?.toString() ?? '';
      if (nav.contains('reelWatchEndpoint') || nav.contains('/shorts/')) isShort = true;
    } catch (_) {}
    final dur = _parseDurationText(lengthText);
    if (lengthText.toLowerCase().contains('short') && dur.inSeconds <= 60) isShort = true;

    return Video(
      id: id,
      title: _text(r['title']),
      thumbnailUrl: thumb,
      channelName: channelName,
      channelId: channelId,
      channelAvatar: avatar,
      viewCount: _parseCount(viewsText),
      duration: isLive ? Duration.zero : dur,
      publishedAt: _text(r['publishedTimeText']),
      description: _text(r['descriptionSnippet']),
      isLive: isLive,
      isShort: isShort,
    );
  }

  /// Walk a nested map/list structure to find a valid 11-char YouTube video ID.
  String? _findVideoIdDeep(dynamic node, {int depth = 0}) {
    if (depth > 6) return null; // guard against excessively deep traversal
    if (node is Map) {
      // Direct videoId field
      final vid = node['videoId']?.toString();
      if (vid != null && vid.length == 11) return vid;
      // Check navigationEndpoint for watch/reel endpoints
      final nav = node['navigationEndpoint'];
      if (nav is Map) {
        final watchId = nav['watchEndpoint']?['videoId']?.toString();
        if (watchId != null && watchId.length == 11) return watchId;
        final reelId = nav['reelWatchEndpoint']?['videoId']?.toString();
        if (reelId != null && reelId.length == 11) return reelId;
      }
      for (final v in node.values) {
        final found = _findVideoIdDeep(v, depth: depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findVideoIdDeep(item, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
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
    // Handle "No views", "Recommended", etc.
    if (RegExp(r'^[a-zA-Z\s]+$').hasMatch(text.trim())) return 0;
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
