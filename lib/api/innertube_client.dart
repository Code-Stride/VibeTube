import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video.dart';
import '../services/hls_parser.dart';
import '../services/caption_service.dart';

/// YouTube InnerTube client — multi-client strategy for maximum playback.
class InnerTubeClient {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  static const List<Map<String, dynamic>> _playerClients = [
    {
      'clientName': 'IOS', 'clientVersion': '20.10.4',
      'deviceMake': 'Apple', 'deviceModel': 'iPhone16,2',
      'osName': 'iPhone', 'osVersion': '18.3.2.22D82',
      'hl': 'en', 'gl': 'US',
      '_ua': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      '_clientNameId': '5',
    },
    {
      'clientName': 'ANDROID', 'clientVersion': '20.10.38',
      'androidSdkVersion': 34, 'osName': 'Android', 'osVersion': '14',
      'hl': 'en', 'gl': 'IN',
      '_ua': 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      '_clientNameId': '3',
    },
    {
      'clientName': 'MEDIACONNECT', 'clientVersion': '6.20250312',
      'hl': 'en', 'gl': 'US',
      '_ua': 'com.google.android.apps.youtube.mediashell/6.20250312 (Linux; U; Android 14)',
      '_clientNameId': '95',
    },
  ];

  static const Map<String, dynamic> _webClient = {
    'hl': 'en', 'gl': 'IN', 'clientName': 'WEB',
    'clientVersion': '2.20250713.00.00',
    'userAgent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  final http.Client _http = http.Client();

  Map<String, String> _headers(String? ua) => {
    'Content-Type': 'application/json',
    'User-Agent': ua ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': '*/*', 'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://www.youtube.com', 'Referer': 'https://www.youtube.com/',
  };

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body,
      {String? userAgent, String? clientNameId, String? clientVersion}) async {
    final uri = Uri.parse('$_baseUrl/$endpoint?prettyPrint=false&key=$_apiKey');
    final headers = {
      ..._headers(userAgent),
      'X-YouTube-Client-Name': clientNameId ?? '1',
      'X-YouTube-Client-Version': clientVersion ?? (_webClient['clientVersion'] as String?) ?? '2.20250713.00.00',
    };
    final res = await _http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 18));
    if (res.statusCode != 200) throw Exception('InnerTube $endpoint HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ═══ Browse / Search ═══

  Future<List<Video>> getTrending({String region = 'IN'}) async {
    final client = {..._webClient, 'gl': region};
    try {
      final response = await _post('browse', {'browseId': 'FEtrending', 'context': {'client': client}}, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.length >= 8) return videos;
    } catch (_) {}
    try {
      final home = await getHomeFeed(region: region);
      if (home.length >= 8) return home;
    } catch (_) {}
    return _buildDiscoverFeed(region: region);
  }

  Future<List<Video>> getHomeFeed({String region = 'IN'}) async {
    final client = {..._webClient, 'gl': region};
    try {
      final response = await _post('browse', {'browseId': 'FEwhat_to_watch', 'context': {'client': client}}, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) return videos;
    } catch (_) {}
    return _buildDiscoverFeed(region: region);
  }

  static const String kFilterVideos = 'EgIQAQ==';
  static const String kFilterShorts = 'EgIYAQ==';
  static const String kFilterLive = 'EgJAAQ==';

  Future<List<Video>> getCategoryFeed(String category, {String region = 'IN'}) async =>
      (await getCategoryPage(category, region: region)).videos;

  /// Category feed as a pageable result, so callers can keep scrolling.
  Future<SearchResult> getCategoryPage(String category,
      {String region = 'IN', String? continuation}) async {
    final c = category.trim().toLowerCase();
    final isIn = region.toUpperCase() == 'IN';
    if (c == 'shorts') {
      final q = isIn ? 'shorts india' : 'shorts';
      var result = await search(q,
          params: kFilterShorts, region: region, continuation: continuation);
      if (result.videos.isEmpty && continuation == null) {
        result = await search('#shorts', params: kFilterShorts, region: region);
      }
      if (result.videos.isEmpty && continuation == null) {
        result = await search('youtube shorts', params: kFilterShorts, region: region);
      }
      return result;
    }
    if (c == 'live') {
      final q = isIn ? 'live news india' : 'live news';
      var result = await search(q,
          params: kFilterLive, region: region, continuation: continuation);
      if (result.videos.isEmpty && continuation == null) {
        result = await search('live', params: kFilterLive, region: region);
      }
      return result;
    }
    final q = _categoryQuery(category, region);
    final result = await search(q,
        params: kFilterVideos, region: region, continuation: continuation);
    if (result.videos.isNotEmpty || continuation != null) return result;
    return search(category, params: kFilterVideos, region: region);
  }

  String _categoryQuery(String category, String region) {
    final c = category.trim().toLowerCase();
    final isIn = region.toUpperCase() == 'IN';
    switch (c) {
      case 'all': return isIn ? 'trending india' : 'trending';
      case 'music': return isIn ? 'bollywood songs' : 'music videos';
      case 'youtube music': return isIn ? 'latest music india 2025' : 'youtube music hits 2025';
      case 'gaming': return isIn ? 'gaming india' : 'gaming';
      case 'news': return isIn ? 'news india today' : 'world news today';
      case 'sports': return isIn ? 'cricket highlights' : 'sports highlights';
      case 'movies': return isIn ? 'bollywood movie trailers' : 'movie trailers';
      case 'education': return isIn ? 'study with me india' : 'education';
      case 'technology': return isIn ? 'tech india' : 'technology';
      case 'comedy': return isIn ? 'indian comedy' : 'comedy';
      default: return category;
    }
  }

  Future<List<Video>> _buildDiscoverFeed({String region = 'IN'}) async {
    final isIn = region.toUpperCase() == 'IN';
    final queries = isIn
        ? ['trending india', 'bollywood songs', 'cricket', 'news india', 'comedy india', 'tech reviews', 'youtube shorts india', 'live news india', 'viral videos india']
        : ['trending', 'music', 'gaming', 'news today', 'sports', 'comedy', 'youtube shorts', 'live', 'viral'];
    final seen = <String>{};
    final out = <Video>[];
    for (var i = 0; i < queries.length; i += 4) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 300));
      final batch = queries.sublist(i, (i + 4).clamp(0, queries.length));
      final results = await Future.wait(batch.map((q) async {
        try { return (await search(q, region: region)).videos; } catch (_) { return <Video>[]; }
      }));
      final lists = results.where((l) => l.isNotEmpty).toList();
      var idx = 0;
      var added = true;
      while (added) {
        added = false;
        for (final list in lists) {
          if (idx < list.length) { final v = list[idx]; if (v.id.isNotEmpty && seen.add(v.id)) { out.add(v); added = true; } }
        }
        idx++;
      }
      if (out.length >= 60) break;
    }
    return out;
  }

  /// Searches, optionally continuing a previous page.
  ///
  /// [region] overrides the client `gl` so the Settings region actually
  /// reaches search — previously every query was hard-coded to the `_webClient`
  /// default regardless of what the user picked.
  Future<SearchResult> search(String query,
      {String? continuation, String? params, String? region}) async {
    final client = Map<String, dynamic>.from(_webClient);
    if (region != null && region.isNotEmpty) client['gl'] = region.toUpperCase();
    // A continuation request must NOT resend query/params: YouTube treats the
    // token as the complete description of the next page.
    final body = continuation != null
        ? <String, dynamic>{'context': {'client': client}, 'continuation': continuation}
        : <String, dynamic>{'query': query, 'context': {'client': client}, 'params': params ?? kFilterVideos};
    try {
      final response = await _post('search', body, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) {
        return SearchResult(videos: videos, continuation: _extractContinuation(response));
      }
    } catch (_) {}
    // The ANDROID client has no continuation support here, so only retry the
    // first page with it; a failed continuation just ends the feed.
    if (continuation != null) return const SearchResult(videos: []);
    try {
      final androidClient = {'clientName': 'ANDROID', 'clientVersion': '20.10.38', 'androidSdkVersion': 34, 'hl': client['hl'] ?? 'en', 'gl': client['gl'] ?? 'IN'};
      final response = await _post('search', {'query': query, 'context': {'client': androidClient}, 'params': params ?? kFilterVideos}, userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip');
      return SearchResult(
        videos: _parseVideosDeep(response),
        continuation: _extractContinuation(response),
      );
    } catch (e) { throw Exception('Search failed: $e'); }
  }

  /// Pulls the "next page" token out of a browse/search response.
  ///
  /// Without this every `SearchResult.continuation` was null, so infinite
  /// scroll and "load more shorts" silently re-requested page 1 forever.
  @visibleForTesting
  static String? extractContinuation(Map<String, dynamic> response) =>
      _extractContinuation(response);

  static String? _extractContinuation(Map<String, dynamic> response) {
    String? token;
    void walk(dynamic node) {
      if (token != null) return;
      if (node is Map) {
        final direct = node['continuationItemRenderer']?['continuationEndpoint']
            ?['continuationCommand']?['token'];
        if (direct is String && direct.isNotEmpty) {
          token = direct;
          return;
        }
        // Older shelf-style responses nest the token differently.
        final legacy = node['nextContinuationData']?['continuation'];
        if (legacy is String && legacy.isNotEmpty) {
          token = legacy;
          return;
        }
        for (final v in node.values) {
          walk(v);
          if (token != null) return;
        }
      } else if (node is List) {
        for (final i in node) {
          walk(i);
          if (token != null) return;
        }
      }
    }
    walk(response);
    return token;
  }

  // ═══ Video Details ═══

  Future<VideoDetails> getVideoDetails(String videoId, {String? region}) async {
    Object? lastError;
    VideoDetails? androidDetails, iosDetails, mediaConnectDetails;

    // Fetch all mobile clients in parallel
    final futures = <Future<void>>[];
    for (final raw in _playerClients) {
      final cfg = Map<String, dynamic>.from(raw);
      // Honour the user's region here too. It previously reached search and
      // browse only, so the player always used the hardcoded IN/US values.
      if (region != null && region.isNotEmpty) cfg['gl'] = region.toUpperCase();
      final ua = cfg.remove('_ua') as String?;
      final name = cfg['clientName']?.toString() ?? '';
      futures.add(() async {
        try {
          final details = await _fetchPlayer(videoId, cfg, ua);
          if (name == 'IOS') { iosDetails = details; }
          else if (name == 'ANDROID') { androidDetails = details; }
          else if (name == 'MEDIACONNECT') { mediaConnectDetails = details; }
        } catch (e) { lastError = e; debugPrint('Client $name failed: $e'); }
      }());
    }
    await Future.wait(futures);

    // WEB client fallback
    VideoDetails? webDetails;
    try { webDetails = await _fetchWebPlayer(videoId); } catch (e) { debugPrint('WEB client failed: $e'); }

    final base = iosDetails ?? androidDetails ?? mediaConnectDetails ?? webDetails;
    if (base == null) throw Exception('No playable stream found. $lastError');

    // Merge formats from all clients
    final formats = <VideoFormat>[...?androidDetails?.formats, ...?iosDetails?.formats, ...?mediaConnectDetails?.formats, ...?webDetails?.formats];
    final seen = <String>{};
    final mergedFormats = <VideoFormat>[];
    for (final f in formats) { if (f.url.isNotEmpty && seen.add(f.url)) mergedFormats.add(f); }
    final formatsFinal = mergedFormats.isNotEmpty ? mergedFormats : base.formats;

    // Best HLS URL
    final liveGuess = (iosDetails?.isLive ?? false) || (androidDetails?.isLive ?? false) || (mediaConnectDetails?.isLive ?? false) || base.isLive;
    String? hls;
    if (liveGuess) {
      hls = androidDetails?.hlsUrl ?? iosDetails?.hlsUrl ?? mediaConnectDetails?.hlsUrl ?? base.hlsUrl;
    } else {
      hls = iosDetails?.hlsUrl ?? androidDetails?.hlsUrl ?? mediaConnectDetails?.hlsUrl ?? base.hlsUrl;
    }

    // Progressive muxed by height
    final progressive = <int, String>{};
    for (final f in formatsFinal.where((f) => f.isMuxed && f.height > 0)) { progressive.putIfAbsent(f.height, () => f.url); }

    // Parse HLS variants
    var hlsVariants = <int, String>{};
    if (hls != null && hls.isNotEmpty) {
      final variants = await HlsParser.parseMaster(hls, headers: const {'User-Agent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)', 'Accept': '*/*'});
      for (final v in variants) { hlsVariants[v.height] = v.url; }
    }
    // Normalize heights
    final normalized = <int, String>{};
    for (final e in hlsVariants.entries) {
      final h = e.key;
      int bucket;
      if (h >= 2000) { bucket = 2160; }
      else if (h >= 1300) { bucket = 1440; }
      else if (h >= 900) { bucket = 1080; }
      else if (h >= 600) { bucket = 720; }
      else if (h >= 420) { bucket = 480; }
      else if (h >= 300) { bucket = 360; }
      else if (h >= 200) { bucket = 240; }
      else { bucket = 144; }
      normalized.putIfAbsent(bucket, () => e.value);
      // Only add the raw height when it isn't already the bucket label.
      if (h != bucket) normalized[h] = e.value;
    }
    hlsVariants = normalized;

    // Metadata from best source
    String bestTitle = '';
    for (final d in [iosDetails, androidDetails, mediaConnectDetails, webDetails, base]) {
      if (d != null && d.title.isNotEmpty) { bestTitle = d.title; break; }
    }
    String bestChannel = '';
    for (final d in [iosDetails, androidDetails, mediaConnectDetails, webDetails, base]) {
      if (d != null && d.channelName.isNotEmpty) { bestChannel = d.channelName; break; }
    }
    // Not every client returns captions (MEDIACONNECT usually does not).
    var bestCaptions = const <CaptionTrack>[];
    for (final d in [webDetails, iosDetails, androidDetails, mediaConnectDetails, base]) {
      if (d != null && d.captionTracks.isNotEmpty) { bestCaptions = d.captionTracks; break; }
    }
    String bestThumb = '';
    for (final d in [iosDetails, androidDetails, mediaConnectDetails, webDetails, base]) {
      if (d != null && d.thumbnailUrl.isNotEmpty) { bestThumb = d.thumbnailUrl; break; }
    }

    return VideoDetails(
      id: base.id, title: bestTitle, description: base.description,
      channelName: bestChannel, channelId: base.channelId,
      viewCount: base.viewCount, duration: base.duration,
      thumbnailUrl: bestThumb, publishedAt: base.publishedAt,
      formats: formatsFinal, hlsUrl: hls,
      dashUrl: base.dashUrl ?? androidDetails?.dashUrl,
      likeCount: base.likeCount, isLive: liveGuess,
      isShort: base.isShort, hlsVariants: hlsVariants,
      progressiveByHeight: progressive,
      captionTracks: bestCaptions,
    );
  }

  /// Cheap single-client stream lookup used by the Shorts feed.
  ///
  /// [getVideoDetails] fans out to every player client *and* downloads and
  /// parses the HLS master playlist — five network round trips per video. The
  /// Shorts pager instantiates one of these per card, so scrolling a 20-item
  /// feed fired ~100 InnerTube requests and reliably tripped rate limiting.
  /// A Short is short, vertical and always available as progressive MP4, so
  /// one client and no manifest parsing is enough.
  Future<String?> getQuickStreamUrl(String videoId) async {
    Object? lastError;
    for (final raw in _playerClients.take(2)) {
      final cfg = Map<String, dynamic>.from(raw);
      final ua = cfg.remove('_ua') as String?;
      try {
        final details = await _fetchPlayer(videoId, cfg, ua);
        final muxed = details.formats
            .where((f) => f.isMuxed && f.url.isNotEmpty)
            .toList()
          ..sort((a, b) => a.height.compareTo(b.height));
        // Smallest stream that still looks decent on a phone.
        for (final f in muxed) {
          if (f.height >= 360) return f.url;
        }
        if (muxed.isNotEmpty) return muxed.last.url;
        final hls = details.hlsUrl;
        if (hls != null && hls.isNotEmpty) return hls;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) debugPrint('getQuickStreamUrl: $lastError');
    return null;
  }

  Future<VideoDetails> _fetchPlayer(String videoId, Map<String, dynamic> client, String? ua) async {
    final body = {
      'videoId': videoId, 'context': {'client': client},
      'playbackContext': {'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'}},
      'contentCheckOk': true, 'racyCheckOk': true,
    };
    final clientNameId = client.remove('_clientNameId') as String?;
    final clientVersion = client['clientVersion'] as String?;
    final response = await _post('player', body, userAgent: ua, clientNameId: clientNameId, clientVersion: clientVersion);
    final status = response['playabilityStatus']?['status']?.toString();
    if (status != null && status != 'OK') {
      throw Exception('Unplayable ($status): ${response['playabilityStatus']?['reason']}');
    }
    return _parseVideoDetails(response, videoId, clientUserAgent: ua);
  }

  Future<VideoDetails> _fetchWebPlayer(String videoId) async {
    final body = {
      'videoId': videoId, 'context': {'client': _webClient},
      'playbackContext': {'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'}},
      'contentCheckOk': true, 'racyCheckOk': true,
    };
    final response = await _post('player', body, userAgent: _webClient['userAgent'] as String, clientNameId: '1', clientVersion: _webClient['clientVersion'] as String);
    final status = response['playabilityStatus']?['status']?.toString();
    if (status != null && status != 'OK') throw Exception('WEB Unplayable: $status');
    return _parseVideoDetails(response, videoId,
        clientUserAgent: _webClient['userAgent'] as String?);
  }

  /// Related videos and comments both live in the same `/next` payload.
  ///
  /// They used to be fetched with two identical POSTs per video open. This
  /// caches the in-flight/last response per video so the second caller reuses
  /// it — halving the request count and keeping the two panes consistent.
  String? _nextCacheVideoId;
  Future<Map<String, dynamic>>? _nextCacheFuture;

  Future<Map<String, dynamic>> _fetchNext(String videoId) {
    if (_nextCacheVideoId == videoId && _nextCacheFuture != null) {
      return _nextCacheFuture!;
    }
    final future = _post(
      'next',
      {'videoId': videoId, 'context': {'client': _webClient}},
      userAgent: _webClient['userAgent'] as String,
    );
    _nextCacheVideoId = videoId;
    _nextCacheFuture = future;
    // A failed request must not be cached, or every retry returns the error.
    future.catchError((Object e) {
      if (_nextCacheVideoId == videoId) {
        _nextCacheVideoId = null;
        _nextCacheFuture = null;
      }
      throw e;
    });
    return future;
  }

  Future<List<Video>> getRelatedVideos(String videoId) async {
    try {
      final response = await _fetchNext(videoId);
      // Drop the video we are already watching from its own "related" list.
      return _parseVideosDeep(response).where((v) => v.id != videoId).toList();
    } catch (e) { debugPrint('getRelatedVideos error: $e'); return []; }
  }

  Future<List<Comment>> getComments(String videoId) async {
    try {
      final response = await _fetchNext(videoId);
      return _parseCommentsDeep(response);
    } catch (e) { debugPrint('getComments error: $e'); return []; }
  }

  /// SponsorBlock segments, fetched through the privacy-preserving endpoint.
  ///
  /// The plain `?videoID=` form tells sponsor.ajay.app exactly what every user
  /// is watching. The documented alternative sends only the first four hex
  /// characters of sha256(videoID); the server returns every video sharing
  /// that prefix and we pick ours locally, so the exact video never leaves the
  /// device.
  Future<List<SponsorSegment>> getSponsorSegments(String videoId) async {
    const categories =
        '%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%2C%22filler%22%5D';
    List<SponsorSegment> parse(List<dynamic> raw) {
      final out = <SponsorSegment>[];
      for (final s in raw) {
        if (s is! Map) continue;
        final seg = s['segment'];
        if (seg is! List || seg.length < 2) continue;
        final start = (seg[0] as num?)?.toDouble();
        final end = (seg[1] as num?)?.toDouble();
        if (start == null || end == null || end <= start) continue;
        out.add(SponsorSegment(
          start: start,
          end: end,
          category: s['category']?.toString() ?? 'sponsor',
        ));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    }

    try {
      final prefix = sha256
          .convert(utf8.encode(videoId))
          .toString()
          .substring(0, 4);
      final uri = Uri.parse(
          'https://sponsor.ajay.app/api/skipSegments/$prefix?categories=$categories');
      final res = await _http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'VibeTube',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data is! List) return [];
      for (final entry in data) {
        if (entry is Map && entry['videoID']?.toString() == videoId) {
          return parse(entry['segments'] as List<dynamic>? ?? const []);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<int?> getDislikeCount(String videoId) async {
    try {
      final uri = Uri.parse('https://returnyoutubedislikeapi.com/votes?videoId=$videoId');
      final res = await _http.get(uri, headers: {'Accept': 'application/json', 'User-Agent': 'VibeTube/1.7'}).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body)['dislikes'] as num?)?.toInt();
    } catch (_) { return null; }
  }

  // ═══ Parsers ═══

  VideoDetails _parseVideoDetails(Map<String, dynamic> response, String videoId,
      {String? clientUserAgent}) {
    final vd = response['videoDetails'] as Map<String, dynamic>? ?? {};
    final sd = response['streamingData'] as Map<String, dynamic>? ?? {};
    final micro = response['microformat']?['playerMicroformatRenderer'] as Map<String, dynamic>?;
    final formats = <dynamic>[...(sd['formats'] as List<dynamic>? ?? const []), ...(sd['adaptiveFormats'] as List<dynamic>? ?? const [])];
    final thumbs = vd['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
    var thumb = thumbs.isNotEmpty ? (thumbs.last['url']?.toString() ?? '') : '';
    if (thumb.startsWith('//')) thumb = 'https:$thumb';
    if (thumb.isEmpty) thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final lengthSec = int.tryParse(vd['lengthSeconds']?.toString() ?? '0') ?? 0;

    return VideoDetails(
      id: vd['videoId']?.toString() ?? videoId,
      title: vd['title']?.toString() ?? '',
      description: vd['shortDescription']?.toString() ?? '',
      channelName: vd['author']?.toString() ?? '',
      channelId: vd['channelId']?.toString() ?? '',
      viewCount: int.tryParse(vd['viewCount']?.toString() ?? '0') ?? 0,
      duration: Duration(seconds: lengthSec),
      thumbnailUrl: thumb,
      publishedAt: micro?['publishDate']?.toString() ?? '',
      formats: _parseFormats(formats, clientUserAgent),
      hlsUrl: sd['hlsManifestUrl']?.toString(),
      dashUrl: sd['dashManifestUrl']?.toString(),
      // InnerTube returns likeCount as a *string* on most clients, so the old
      // `as num?` cast always produced 0 (and would throw on a plain cast).
      likeCount: _parseLikeCount(vd['likeCount']),
      isLive: vd['isLiveContent'] == true || vd['isLive'] == true ||
          (vd['isUpcoming'] != true && lengthSec == 0 && (sd['hlsManifestUrl'] != null || sd['dashManifestUrl'] != null)),
      captionTracks: CaptionService.parseTracks(response),
      isShort: lengthSec > 0 && lengthSec <= 60 &&
          (vd['title']?.toString().toLowerCase().contains('#short') == true || (micro?['isShort'] == true)),
    );
  }

  List<VideoFormat> _parseFormats(List<dynamic> formats, [String? clientUserAgent]) {
    final out = <VideoFormat>[];
    for (final f in formats) {
      if (f is! Map) continue;
      final String url = f['url']?.toString() ?? '';
      if (url.isEmpty) {
        // signatureCipher formats need the `s` parameter descrambled by
        // YouTube's player JS before the URL works. We don't ship a JS
        // interpreter, so the old code's "just use the bare url param"
        // shortcut produced a URL that always 403s. Emitting it made
        // bestMuxedUrl/urlForQuality pick a dead stream over a working one,
        // which is worse than not offering the format at all — the IOS /
        // ANDROID clients in _playerClients return unciphered URLs anyway.
        continue;
      }
      final mime = (f['mimeType']?.toString() ?? '').toLowerCase();
      final hasVideo = mime.contains('video');
      final hasAudioCodec = mime.contains('mp4a') || mime.contains('opus') || f['audioQuality'] != null;
      final isAudioOnly = mime.startsWith('audio/');
      final isMuxed = hasVideo && hasAudioCodec && !isAudioOnly;
      final isVideoOnly = hasVideo && !isMuxed && !isAudioOnly;
      out.add(VideoFormat(
        url: url, quality: f['qualityLabel']?.toString() ?? f['quality']?.toString() ?? 'Unknown',
        mimeType: f['mimeType']?.toString() ?? '', width: f['width'] as int? ?? 0, height: f['height'] as int? ?? 0,
        bitrate: f['bitrate'] as int? ?? 0, itag: f['itag'] as int? ?? 0,
        isVideoOnly: isVideoOnly, isAudioOnly: isAudioOnly,
        clientUserAgent: clientUserAgent ?? '',
        hasAudio: isAudioOnly || isMuxed || f['audioQuality'] != null, hasVideo: hasVideo,
      ));
    }
    return out;
  }

  List<Video> _parseVideosDeep(Map<String, dynamic> response) {
    final videos = <Video>[];
    void walk(dynamic node) {
      if (node is Map) {
        for (final key in ['videoRenderer', 'compactVideoRenderer', 'gridVideoRenderer', 'playlistVideoRenderer', 'reelItemRenderer', 'shortsLockupViewModel']) {
          if (node[key] is Map) {
            final map = Map<String, dynamic>.from(node[key] as Map);
            Video? v;
            if (key == 'reelItemRenderer' || key == 'shortsLockupViewModel') { v = _extractShort(map, key); }
            else { v = _extractVideo(map); }
            if (v != null) videos.add(v);
          }
        }
        if (node['lockupViewModel'] is Map) { final v = _extractLockup(Map<String, dynamic>.from(node['lockupViewModel'] as Map)); if (v != null) videos.add(v); }
        // The explicit richItemRenderer hop is redundant: the generic
        // node.values walk below already reaches ['content']. Doing both
        // visited that subtree twice on every feed parse.
        for (final v in node.values) { walk(v); }
      } else if (node is List) { for (final i in node) { walk(i); } }
    }
    walk(response);
    final seen = <String>{};
    return videos.where((v) => v.id.isNotEmpty && seen.add(v.id)).toList();
  }

  Video? _extractShort(Map<String, dynamic> r, String kind) {
    try {
      String id = '', title = '', thumb = '', channel = '';
      if (kind == 'reelItemRenderer') {
        id = r['videoId']?.toString() ?? r['navigationEndpoint']?['reelWatchEndpoint']?['videoId']?.toString() ?? '';
        title = _text(r['headline']); if (title.isEmpty) title = _text(r['overlayMetadata']?['primaryText']);
        final th = r['thumbnail']?['thumbnails'] as List? ?? r['thumbnails'] as List? ?? const [];
        if (th.isNotEmpty) thumb = th.last['url']?.toString() ?? '';
        channel = _text(r['overlayMetadata']?['secondaryText']);
      } else {
        id = r['onTap']?['innertubeCommand']?['reelWatchEndpoint']?['videoId']?.toString() ?? r['entityId']?.toString().replaceAll('shorts-shelf-item-', '') ?? '';
        if (id.contains('-')) { final parts = id.split('-'); if (parts.last.length == 11) id = parts.last; }
        title = _text(r['overlayMetadata']?['primaryText']); if (title.isEmpty) title = r['accessibilityText']?.toString() ?? '';
        final th = r['thumbnail']?['sources'] as List? ?? r['thumbnailViewModel']?['image']?['sources'] as List? ?? const [];
        if (th.isNotEmpty) thumb = th.last['url']?.toString() ?? '';
      }
      if (id.isEmpty || id.length < 10) return null;
      if (thumb.startsWith('//')) thumb = 'https:$thumb';
      if (thumb.isEmpty) thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
      return Video(id: id, title: title.isEmpty ? 'Short' : title, thumbnailUrl: thumb, channelName: channel, duration: const Duration(seconds: 30), isShort: true);
    } catch (_) { return null; }
  }

  Video? _extractLockup(Map<String, dynamic> r) {
    try {
      String id = r['contentId']?.toString() ?? '';
      if (id.isEmpty || id.length != 11) id = _findVideoIdDeep(r) ?? '';
      if (id.length != 11) return null;
      String title = '', thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
      void scan(dynamic n) { if (n is Map) { if (n['text'] is Map) { final tx = _text(n['text']); if (title.isEmpty && tx.length > 3) title = tx; } for (final v in n.values) { scan(v); } } else if (n is List) { for (final i in n) { scan(i); } } }
      scan(r['metadata']);
      return Video(
        id: id,
        title: title.isEmpty ? 'Video' : title,
        thumbnailUrl: thumb,
        isLive: _lockupIsLive(r),
      );
    } catch (_) { return null; }
  }

  /// Detects a live badge on a lockup renderer.
  ///
  /// The old check stringified the whole renderer and looked for "LIVE"
  /// anywhere in it, so any video whose title contained "live" — "Delivery",
  /// "Oliver", "Live Aid documentary" — was rendered with a red LIVE badge and
  /// then routed down the live-only HLS path, which broke normal playback.
  /// Only real badge/overlay markers count now.
  @visibleForTesting
  static bool lockupIsLive(Map<String, dynamic> r) => _lockupIsLive(r);

  static bool _lockupIsLive(Map<String, dynamic> r) {
    var live = false;
    void walk(dynamic node) {
      if (live) return;
      if (node is Map) {
        final style = node['style']?.toString().toUpperCase() ?? '';
        if (style.contains('BADGE_STYLE_TYPE_LIVE') ||
            style.contains('LIVE_NOW')) {
          live = true;
          return;
        }
        final badgeType = node['badgeType']?.toString().toUpperCase() ?? '';
        if (badgeType.contains('LIVE')) {
          live = true;
          return;
        }
        if (node['isLive'] == true || node['isLiveNow'] == true) {
          live = true;
          return;
        }
        for (final v in node.values) {
          walk(v);
          if (live) return;
        }
      } else if (node is List) {
        for (final i in node) {
          walk(i);
          if (live) return;
        }
      }
    }
    walk(r);
    return live;
  }

  /// `likeCount` arrives as "1,234,567", "1.2M" or a bare int depending on the
  /// client, so route everything through the shared count parser.
  static int _parseLikeCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    return parseCount(raw.toString());
  }

  List<Comment> _parseCommentsDeep(Map<String, dynamic> response) {
    final comments = <Comment>[];
    void walk(dynamic node) {
      if (node is Map) {
        Map? cr = node['commentRenderer'] as Map?;
        cr ??= node['commentThreadRenderer']?['comment']?['commentRenderer'] as Map?;
        if (cr != null) { comments.add(Comment(id: cr['commentId']?.toString() ?? '', author: _text(cr['authorText']), authorAvatar: (cr['authorThumbnail']?['thumbnails'] as List?)?.last?['url']?.toString() ?? '', text: _text(cr['contentText']), likeCount: _parseCount(_text(cr['voteCount'])), publishedAt: _text(cr['publishedTimeText']))); }
        for (final v in node.values) { walk(v); }
      } else if (node is List) { for (final i in node) { walk(i); } }
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
    try { channelId = r['ownerText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString() ?? r['shortBylineText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString() ?? ''; } catch (_) {}
    String avatar = '';
    try { final ch = r['channelThumbnailSupportedRenderers']?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails'] as List?; if (ch != null && ch.isNotEmpty) avatar = ch.last['url']?.toString() ?? ''; } catch (_) {}
    final viewsText = _text(r['viewCountText']).isNotEmpty ? _text(r['viewCountText']) : _text(r['shortViewCountText']);
    final lengthText = _text(r['lengthText']);
    var isLive = false;
    for (final b in (r['badges'] as List? ?? const [])) { final label = b is Map ? '${_text(b['metadataBadgeRenderer']?['label'])} ${b['metadataBadgeRenderer']?['style']?.toString() ?? ''}' : ''; if (label.toUpperCase().contains('LIVE')) isLive = true; }
    if (r['thumbnailOverlays'] is List) { for (final o in r['thumbnailOverlays']) { if (o.toString().toUpperCase().contains('LIVE')) isLive = true; } }
    var isShort = false;
    try { final nav = r['navigationEndpoint']?.toString() ?? ''; if (nav.contains('reelWatchEndpoint') || nav.contains('/shorts/')) isShort = true; } catch (_) {}
    final dur = _parseDurationText(lengthText);
    if (lengthText.toLowerCase().contains('short') && dur.inSeconds <= 60) isShort = true;
    return Video(id: id, title: _text(r['title']), thumbnailUrl: thumb, channelName: channelName, channelId: channelId, channelAvatar: avatar, viewCount: _parseCount(viewsText), duration: isLive ? Duration.zero : dur, publishedAt: _text(r['publishedTimeText']), description: _text(r['descriptionSnippet']), isLive: isLive, isShort: isShort);
  }

  String? _findVideoIdDeep(dynamic node, {int depth = 0}) {
    if (depth > 6) return null;
    if (node is Map) {
      final vid = node['videoId']?.toString();
      if (vid != null && vid.length == 11) return vid;
      final nav = node['navigationEndpoint'];
      if (nav is Map) {
        final watchId = nav['watchEndpoint']?['videoId']?.toString();
        if (watchId != null && watchId.length == 11) return watchId;
        final reelId = nav['reelWatchEndpoint']?['videoId']?.toString();
        if (reelId != null && reelId.length == 11) return reelId;
      }
      for (final v in node.values) { final found = _findVideoIdDeep(v, depth: depth + 1); if (found != null) return found; }
    } else if (node is List) { for (final item in node) { final found = _findVideoIdDeep(item, depth: depth + 1); if (found != null) return found; } }
    return null;
  }

  String _text(dynamic o) {
    if (o == null) return '';
    if (o is String) return o;
    if (o is Map) { if (o['simpleText'] != null) return o['simpleText'].toString(); if (o['runs'] is List) return (o['runs'] as List).map((r) => r['text'] ?? '').join(); }
    return '';
  }

  /// Parses view/like counts such as "1.2M views", "1,234,567 views",
  /// "4.2 lakh views" or "1.5 करोड़ बार देखा गया".
  ///
  /// The app ships with `gl=IN` by default, and YouTube then localises counts
  /// using the Indian numbering system. Handling only K/M/B meant "4.2 lakh
  /// views" parsed as 4 views, so popular videos looked unwatched.
  static int parseCount(String text) {
    if (text.isEmpty) return 0;
    final trimmed = text.trim();
    if (RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmed)) return 0;

    final lower = trimmed.toLowerCase();
    // Grab the numeric token *with* its separators so they can be interpreted
    // in context. Blindly stripping commas broke locales that use them as the
    // decimal mark ("1,5 Mio."), and leaving dots in broke locales that group
    // with them ("1.234.567" parsed as 1).
    final token = RegExp(r'[\d][\d.,\u00A0\u202F ]*[\d]|[\d]').firstMatch(trimmed);
    if (token == null) {
      return int.tryParse(trimmed.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    // Anchored: only a suffix directly after the number counts, so a stray
    // "t" inside a trailing word can't be read as "trillion".
    final suffixMatch =
        RegExp(r'^\s*([KMBTkmbt])\b').firstMatch(trimmed.substring(token.end));
    final n = _parseLocalisedNumber(token.group(0)!);

    // Word-based multipliers are checked first: the single-letter suffix group
    // below cannot match them.
    const wordMultipliers = <String, double>{
      'crore': 1e7, 'करोड़': 1e7, 'कोटि': 1e7,
      'lakh': 1e5, 'lac': 1e5, 'लाख': 1e5,
      'thousand': 1e3, 'हज़ार': 1e3, 'हजार': 1e3,
      'million': 1e6, 'billion': 1e9, 'trillion': 1e12,
      // Common non-English abbreviations YouTube serves for other locales.
      'mrd': 1e9, 'mio': 1e6, 'tsd': 1e3, 'mio.': 1e6,
    };
    for (final entry in wordMultipliers.entries) {
      // Word-boundary match. A bare contains() meant any string holding "lac"
      // — most obviously "black" — was multiplied by 100,000. The boundary is
      // letter-based so "1.2mio." and "5 lakh," still match.
      final key = RegExp.escape(entry.key);
      if (RegExp('(?:^|[^a-z])$key(?:\$|[^a-z])').hasMatch(lower)) {
        return (n * entry.value).round();
      }
    }

    switch ((suffixMatch?.group(1) ?? '').toUpperCase()) {
      case 'K': return (n * 1e3).round();
      case 'M': return (n * 1e6).round();
      case 'B': return (n * 1e9).round();
      case 'T': return (n * 1e12).round();
      default: return n.round();
    }
  }

  /// Turns a locale-formatted numeric token into a double.
  ///
  /// Handles `1,234,567` (en), `1.234.567` (de/es), `1,5` (de decimal),
  /// `1.5` (en decimal) and thin/non-breaking space grouping (fr).
  @visibleForTesting
  static double parseLocalisedNumber(String raw) => _parseLocalisedNumber(raw);

  static double _parseLocalisedNumber(String raw) {
    // Spaces are always grouping separators, never decimal marks.
    var t = raw.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (t.isEmpty) return 0;

    final hasDot = t.contains('.');
    final hasComma = t.contains(',');

    if (hasDot && hasComma) {
      // Whichever comes last is the decimal separator.
      final decimal = t.lastIndexOf('.') > t.lastIndexOf(',') ? '.' : ',';
      final grouping = decimal == '.' ? ',' : '.';
      t = t.replaceAll(grouping, '').replaceAll(decimal, '.');
      return double.tryParse(t) ?? 0;
    }

    if (hasDot || hasComma) {
      final sep = hasDot ? '.' : ',';
      final parts = t.split(sep);
      final isGrouped = parts.length > 1 &&
          parts.first.isNotEmpty &&
          parts.first.length <= 3 &&
          parts.skip(1).every((p) => p.length == 3);
      if (isGrouped) return double.tryParse(parts.join()) ?? 0;
      return double.tryParse(t.replaceAll(sep, '.')) ?? 0;
    }

    return double.tryParse(t) ?? 0;
  }

  int _parseCount(String text) => parseCount(text);

  /// Parses "1:23:45" / "12:34" duration labels.
  ///
  /// Uses tryParse rather than parse-inside-try: YouTube pads these labels
  /// with stray characters (RTL marks, non-breaking spaces) and a single bad
  /// component threw away an otherwise valid duration.
  static Duration parseDurationText(String text) {
    if (text.isEmpty) return Duration.zero;
    final parts = text
        .split(':')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^\d]'), '')) ?? -1)
        .toList();
    if (parts.any((p) => p < 0)) return Duration.zero;
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0], seconds: parts[1]);
    }
    if (parts.length == 1) return Duration(seconds: parts[0]);
    return Duration.zero;
  }

  Duration _parseDurationText(String text) => parseDurationText(text);

  void dispose() => _http.close();
}
