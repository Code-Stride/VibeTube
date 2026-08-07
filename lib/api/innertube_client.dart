import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video.dart';
import '../services/hls_parser.dart';

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

  Future<List<Video>> getCategoryFeed(String category, {String region = 'IN'}) async {
    final c = category.trim().toLowerCase();
    final isIn = region.toUpperCase() == 'IN';
    if (c == 'shorts') {
      final q = isIn ? 'shorts india' : 'shorts';
      var result = await search(q, params: kFilterShorts);
      if (result.videos.isEmpty) result = await search('#shorts', params: kFilterShorts);
      if (result.videos.isEmpty) result = await search('youtube shorts', params: kFilterShorts);
      return result.videos;
    }
    if (c == 'live') {
      final q = isIn ? 'live news india' : 'live news';
      var result = await search(q, params: kFilterLive);
      if (result.videos.isEmpty) result = await search('live', params: kFilterLive);
      return result.videos;
    }
    final q = _categoryQuery(category, region);
    final result = await search(q, params: kFilterVideos);
    if (result.videos.isNotEmpty) return result.videos;
    return (await search(category, params: kFilterVideos)).videos;
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
        try { return (await search(q)).videos; } catch (_) { return <Video>[]; }
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

  Future<SearchResult> search(String query, {String? continuation, String? params}) async {
    final client = Map<String, dynamic>.from(_webClient);
    final body = <String, dynamic>{'query': query, 'context': {'client': client}, 'params': params ?? kFilterVideos};
    // A continuation request must not also carry the original query/params.
    if (continuation != null && continuation.isNotEmpty) {
      body
        ..remove('query')
        ..remove('params')
        ..['continuation'] = continuation;
    }
    try {
      final response = await _post('search', body, userAgent: _webClient['userAgent'] as String);
      final videos = _parseVideosDeep(response);
      if (videos.isNotEmpty) {
        return SearchResult(videos: videos, continuation: _findContinuation(response));
      }
    } catch (_) {}
    try {
      final androidClient = {'clientName': 'ANDROID', 'clientVersion': '20.10.38', 'androidSdkVersion': 34, 'hl': client['hl'] ?? 'en', 'gl': client['gl'] ?? 'IN'};
      final aBody = <String, dynamic>{'context': {'client': androidClient}};
      if (continuation != null && continuation.isNotEmpty) {
        aBody['continuation'] = continuation;
      } else {
        aBody['query'] = query;
        aBody['params'] = params ?? kFilterVideos;
      }
      final response = await _post('search', aBody, userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip');
      return SearchResult(videos: _parseVideosDeep(response), continuation: _findContinuation(response));
    } catch (e) { throw Exception('Search failed: $e'); }
  }

  /// Walks a response for the "load more" token.
  ///
  /// Without this, `SearchResult.continuation` was always null and every
  /// "load more" call re-requested page 1 — the dedupe filter then dropped
  /// everything, so feeds silently stopped after the first page.
  String? _findContinuation(dynamic node, {int depth = 0}) {
    if (depth > 12) return null;
    if (node is Map) {
      final token = node['continuationCommand']?['token'] ??
          node['nextContinuationData']?['continuation'] ??
          node['reloadContinuationData']?['continuation'];
      if (token is String && token.isNotEmpty) return token;
      for (final v in node.values) {
        final found = _findContinuation(v, depth: depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _findContinuation(v, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  // ═══ Video Details ═══

  Future<VideoDetails> getVideoDetails(String videoId) async {
    Object? lastError;
    VideoDetails? androidDetails, iosDetails, mediaConnectDetails;

    // Fetch all mobile clients in parallel
    final futures = <Future<void>>[];
    for (final raw in _playerClients) {
      final cfg = Map<String, dynamic>.from(raw);
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
      // Video-only renditions are unusable on their own — their audio lives in
      // a separate EXT-X-MEDIA group that only the master playlist references.
      // Locking to one would play a silent video, so they are skipped and the
      // master playlist stays the fallback for those heights.
      for (final v in variants.where((v) => v.hasAudio)) {
        hlsVariants[v.height] = v.url;
      }
    }
    // Normalize odd encoder heights (1088, 722, ...) onto the standard ladder.
    // Only the bucket is kept: previously the raw height was inserted too,
    // which double-counted streams in the quality sheet and gave the
    // nearest-match lookup two competing candidates for the same rendition.
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
    String bestThumb = '';
    for (final d in [iosDetails, androidDetails, mediaConnectDetails, webDetails, base]) {
      if (d != null && d.thumbnailUrl.isNotEmpty) { bestThumb = d.thumbnailUrl; break; }
    }
    // The WEB client is the one that reliably returns the caption tracklist.
    var captions = const <CaptionTrack>[];
    for (final d in [webDetails, iosDetails, androidDetails, mediaConnectDetails, base]) {
      if (d != null && d.captionTracks.isNotEmpty) { captions = d.captionTracks; break; }
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
      captionTracks: captions,
    );
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
    return _parseVideoDetails(response, videoId);
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
    return _parseVideoDetails(response, videoId);
  }

  /// Related videos + comments in a single `next` round-trip.
  ///
  /// These were two identical POSTs fired in parallel, doubling a ~1 MB
  /// download on every video open.
  Future<WatchNextData> getWatchNext(String videoId) async {
    try {
      final response = await _post('next', {'videoId': videoId, 'context': {'client': _webClient}}, userAgent: _webClient['userAgent'] as String);
      return WatchNextData(
        related: _parseVideosDeep(response),
        comments: _parseCommentsDeep(response),
      );
    } catch (e) {
      debugPrint('getWatchNext error: $e');
      return const WatchNextData();
    }
  }

  Future<List<Video>> getRelatedVideos(String videoId) async =>
      (await getWatchNext(videoId)).related;

  Future<List<Comment>> getComments(String videoId) async =>
      (await getWatchNext(videoId)).comments;

  Future<List<SponsorSegment>> getSponsorSegments(String videoId) async {
    try {
      final uri = Uri.parse('https://sponsor.ajay.app/api/skipSegments?videoID=$videoId&categories=%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%2C%22filler%22%5D');
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as List<dynamic>;
      return data.map((s) {
        final seg = s['segment'] as List<dynamic>;
        return SponsorSegment(start: (seg[0] as num).toDouble(), end: (seg[1] as num).toDouble(), category: s['category']?.toString() ?? 'sponsor');
      }).toList();
    } catch (_) { return []; }
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

  VideoDetails _parseVideoDetails(Map<String, dynamic> response, String videoId) {
    final vd = response['videoDetails'] as Map<String, dynamic>? ?? {};
    final sd = response['streamingData'] as Map<String, dynamic>? ?? {};
    final micro = response['microformat']?['playerMicroformatRenderer'] as Map<String, dynamic>?;
    final formats = <dynamic>[...(sd['formats'] as List<dynamic>? ?? const []), ...(sd['adaptiveFormats'] as List<dynamic>? ?? const [])];
    var thumb = _lastThumbUrl(vd['thumbnail']?['thumbnails']);
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
      formats: _parseFormats(formats),
      hlsUrl: sd['hlsManifestUrl']?.toString(),
      dashUrl: sd['dashManifestUrl']?.toString(),
      likeCount: _asInt(vd['likeCount']),
      captionTracks: _parseCaptionTracks(response),
      isLive: vd['isLiveContent'] == true || vd['isLive'] == true ||
          (vd['isUpcoming'] != true && lengthSec == 0 && (sd['hlsManifestUrl'] != null || sd['dashManifestUrl'] != null)),
      isShort: lengthSec > 0 && lengthSec <= 60 &&
          (vd['title']?.toString().toLowerCase().contains('#short') == true || (micro?['isShort'] == true)),
    );
  }

  /// Reads the caption tracklist straight out of the player response.
  ///
  /// CaptionService used to re-download the entire watch page (1-3 MB) just to
  /// find this same object, and silently returned nothing whenever YouTube
  /// served a consent interstitial instead of the real page.
  List<CaptionTrack> _parseCaptionTracks(Map<String, dynamic> response) {
    try {
      final list = response['captions']?['playerCaptionsTracklistRenderer']
          ?['captionTracks'];
      if (list is! List) return const [];
      final out = <CaptionTrack>[];
      for (final t in list) {
        if (t is! Map) continue;
        final baseUrl = t['baseUrl']?.toString() ?? '';
        if (baseUrl.isEmpty) continue;
        final lang = t['languageCode']?.toString() ?? '';
        var name = _text(t['name']);
        if (name.isEmpty) name = lang;
        out.add(CaptionTrack(
          languageCode: lang,
          name: name,
          baseUrl: baseUrl,
          isAutoGenerated: t['kind']?.toString() == 'asr',
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<VideoFormat> _parseFormats(List<dynamic> formats) {
    final out = <VideoFormat>[];
    for (final f in formats) {
      if (f is! Map) continue;
      String url = f['url']?.toString() ?? '';
      if (url.isEmpty) {
        final sc = f['signatureCipher']?.toString() ?? '';
        if (sc.isNotEmpty) { final params = Uri.splitQueryString(sc); url = params['url'] ?? ''; }
      }
      if (url.isEmpty) continue;
      final mime = (f['mimeType']?.toString() ?? '').toLowerCase();
      final hasVideo = mime.contains('video');
      final hasAudioCodec = mime.contains('mp4a') || mime.contains('opus') || f['audioQuality'] != null;
      final isAudioOnly = mime.startsWith('audio/');
      final isMuxed = hasVideo && hasAudioCodec && !isAudioOnly;
      final isVideoOnly = hasVideo && !isMuxed && !isAudioOnly;
      out.add(VideoFormat(
        url: url, quality: f['qualityLabel']?.toString() ?? f['quality']?.toString() ?? 'Unknown',
        mimeType: f['mimeType']?.toString() ?? '', width: _asInt(f['width']), height: _asInt(f['height']),
        bitrate: _asInt(f['bitrate']), itag: _asInt(f['itag']),
        isVideoOnly: isVideoOnly, isAudioOnly: isAudioOnly,
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
        if (node['richItemRenderer'] is Map) { walk(node['richItemRenderer']['content']); }
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
      final blob = r.toString().toUpperCase();
      return Video(id: id, title: title.isEmpty ? 'Video' : title, thumbnailUrl: thumb, isLive: blob.contains('LIVE') || blob.contains('BADGE_STYLE_TYPE_LIVE'));
    } catch (_) { return null; }
  }

  List<Comment> _parseCommentsDeep(Map<String, dynamic> response) {
    final comments = <Comment>[];
    void walk(dynamic node) {
      if (node is Map) {
        Map? cr = node['commentRenderer'] as Map?;
        cr ??= node['commentThreadRenderer']?['comment']?['commentRenderer'] as Map?;
        if (cr != null) {
          // `.last` throws StateError on an empty list, so a single avatar-less
          // comment used to wipe out the whole thread.
          comments.add(Comment(
            id: cr['commentId']?.toString() ?? '',
            author: _text(cr['authorText']),
            authorAvatar: _lastThumbUrl(cr['authorThumbnail']?['thumbnails']),
            text: _text(cr['contentText']),
            likeCount: _parseCount(_text(cr['voteCount'])),
            publishedAt: _text(cr['publishedTimeText']),
          ));
        }
        for (final v in node.values) { walk(v); }
      } else if (node is List) { for (final i in node) { walk(i); } }
    }
    walk(response);
    return comments;
  }

  /// Safely reads the highest-resolution URL out of a YouTube `thumbnails`
  /// array. Returns '' for anything that is not a non-empty list of maps —
  /// `.last` on an empty list throws, and YouTube occasionally sends a shape
  /// we do not expect.
  static String _lastThumbUrl(dynamic thumbs) {
    if (thumbs is! List || thumbs.isEmpty) return '';
    final last = thumbs.last;
    if (last is! Map) return '';
    return last['url']?.toString() ?? '';
  }

  /// Parses a JSON number that YouTube sometimes sends as a string
  /// (`"likeCount": "1234"`), which used to blow up an `as num?` cast.
  static int _asInt(dynamic v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    if (v is String) return num.tryParse(v)?.toInt() ?? fallback;
    return fallback;
  }

  /// One malformed entry must never take down the whole feed: `walk()` runs
  /// this for every renderer it finds, and an uncaught throw here propagated
  /// all the way out of `_parseVideosDeep`, returning an empty list.
  Video? _extractVideo(Map<String, dynamic> r) {
    try {
      return _extractVideoUnsafe(r);
    } catch (_) {
      return null;
    }
  }

  Video? _extractVideoUnsafe(Map<String, dynamic> r) {
    final id = r['videoId']?.toString();
    if (id == null || id.isEmpty) return null;
    var thumb = _lastThumbUrl(r['thumbnail']?['thumbnails']);
    if (thumb.startsWith('//')) thumb = 'https:$thumb';
    if (thumb.isEmpty) thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
    String channelName = _text(r['ownerText']);
    if (channelName.isEmpty) channelName = _text(r['shortBylineText']);
    if (channelName.isEmpty) channelName = _text(r['longBylineText']);
    String channelId = '';
    try { channelId = r['ownerText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString() ?? r['shortBylineText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString() ?? ''; } catch (_) {}
    String avatar = '';
    try { avatar = _lastThumbUrl(r['channelThumbnailSupportedRenderers']?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails']); } catch (_) {}
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
    final cleaned = trimmed.replaceAll(',', '');
    final number = RegExp(r'[\d.]+').firstMatch(cleaned);
    if (number == null) {
      return int.tryParse(cleaned.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    final n = double.tryParse(number.group(0)!) ?? 0;

    // Word-based multipliers are checked first: the single-letter suffix below
    // cannot express them.
    const wordMultipliers = <String, double>{
      'crore': 1e7, 'करोड़': 1e7, 'कोटि': 1e7,
      'lakh': 1e5, 'lac': 1e5, 'लाख': 1e5,
      'thousand': 1e3, 'हज़ार': 1e3, 'हजार': 1e3,
      'million': 1e6, 'billion': 1e9,
    };
    // Word-boundary matched: a bare `contains` made 'lac' fire inside
    // "black", "place" and "palace".
    for (final entry in wordMultipliers.entries) {
      final re = RegExp(
        '(^|[^\\p{L}])${RegExp.escape(entry.key)}([^\\p{L}]|\$)',
        unicode: true,
      );
      if (re.hasMatch(lower)) return (n * entry.value).round();
    }

    // The suffix must be a standalone letter directly after the number, e.g.
    // "1.2M views" or "532K". Making it a bare optional group meant the "b" of
    // "5 black friday deals" was read as "billion".
    final suffix = RegExp(
      r'([\d.]+)\s*([KMBT])(?![\p{L}])',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(cleaned);
    if (suffix == null) return n.round();

    final base = double.tryParse(suffix.group(1)!) ?? n;
    switch (suffix.group(2)!.toUpperCase()) {
      case 'K':
        return (base * 1e3).round();
      case 'M':
        return (base * 1e6).round();
      case 'B':
        return (base * 1e9).round();
      case 'T':
        return (base * 1e12).round();
      default:
        return base.round();
    }
  }

  int _parseCount(String text) => parseCount(text);

  // ---- Test hooks -----------------------------------------------------
  // These parsers are the ones that historically took down a whole feed or
  // comment thread, so they are exercised directly by the unit tests.

  @visibleForTesting
  List<Video> parseVideosForTest(Map<String, dynamic> response) =>
      _parseVideosDeep(response);

  @visibleForTesting
  List<Comment> parseCommentsForTest(Map<String, dynamic> response) =>
      _parseCommentsDeep(response);

  @visibleForTesting
  VideoDetails parseDetailsForTest(
          Map<String, dynamic> response, String videoId) =>
      _parseVideoDetails(response, videoId);

  @visibleForTesting
  String? findContinuationForTest(Map<String, dynamic> response) =>
      _findContinuation(response);

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
