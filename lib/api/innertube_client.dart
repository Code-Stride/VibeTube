import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video.dart';

/// YouTube InnerTube client with multiple player clients for reliable streams.
class InnerTubeClient {
  static const String _baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  // Clients known to return plain (non-ciphered) stream URLs
  static const List<Map<String, dynamic>> _playerClients = [
    {
      'clientName': 'IOS',
      'clientVersion': '20.10.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
      'userAgent':
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      'hl': 'en',
      'gl': 'US',
    },
    {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
      'androidSdkVersion': 30,
      'userAgent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      'hl': 'en',
      'gl': 'US',
    },
    {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.60.19',
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'androidSdkVersion': 32,
      'userAgent':
          'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L) gzip',
      'hl': 'en',
      'gl': 'US',
    },
  ];

  static const Map<String, dynamic> _webContext = {
    'client': {
      'hl': 'en',
      'gl': 'US',
      'clientName': 'WEB',
      'clientVersion': '2.20250312.00.00',
      'userAgent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    }
  };

  final http.Client _http = http.Client();

  Map<String, String> _headers({String? userAgent}) => {
        'Content-Type': 'application/json',
        'User-Agent': userAgent ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'X-YouTube-Client-Name': '1',
        'X-YouTube-Client-Version': '2.20250312.00.00',
      };

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? userAgent,
  }) async {
    final url = Uri.parse('$_baseUrl/$endpoint?prettyPrint=false&key=$_apiKey');
    final res = await _http
        .post(url, headers: _headers(userAgent: userAgent), body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('InnerTube $endpoint failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Public API ----------

  Future<List<Video>> getTrending({String region = 'IN'}) async {
    try {
      final response = await _post('browse', {
        'browseId': 'FEtrending',
        'context': {
          'client': {..._webContext['client'] as Map<String, dynamic>, 'gl': region}
        },
      });
      final videos = _parseRichGrid(response);
      if (videos.isNotEmpty) return videos;
    } catch (_) {}
    // fallback home
    return getHomeFeed(region: region);
  }

  Future<List<Video>> getHomeFeed({String region = 'IN'}) async {
    final response = await _post('browse', {
      'browseId': 'FEwhat_to_watch',
      'context': {
        'client': {..._webContext['client'] as Map<String, dynamic>, 'gl': region}
      },
    });
    return _parseRichGrid(response);
  }

  Future<SearchResult> search(String query, {String? continuation}) async {
    final body = <String, dynamic>{
      'query': query,
      'context': _webContext,
      'params': 'EgIQAQ%3D%3D',
    };
    if (continuation != null) body['continuation'] = continuation;
    final response = await _post('search', body);
    return _parseSearch(response);
  }

  /// Fetches playable stream. Tries multiple clients until muxed URL found.
  Future<VideoDetails> getVideoDetails(String videoId) async {
    Object? lastError;
    VideoDetails? withHls;
    VideoDetails? withMuxed;
    VideoDetails? any;

    // Try clients; merge best stream sources.
    for (final client in _playerClients) {
      try {
        final details = await _fetchPlayer(videoId, client);
        any ??= details;
        if (details.hlsUrl != null && details.hlsUrl!.isNotEmpty) {
          withHls ??= details;
        }
        if (details.bestMuxedUrl != null) {
          withMuxed ??= details;
        }
        // Fast path: both HLS + muxed collected
        if (withHls != null && withMuxed != null) break;
      } catch (e) {
        lastError = e;
      }
    }

    // Prefer HLS (higher quality multi-bitrate) with muxed formats as backup.
    if (withHls != null) {
      if (withMuxed != null && withHls.formats.isEmpty) {
        return VideoDetails(
          id: withHls.id,
          title: withHls.title,
          description: withHls.description,
          channelName: withHls.channelName,
          channelId: withHls.channelId,
          channelAvatar: withHls.channelAvatar,
          viewCount: withHls.viewCount,
          duration: withHls.duration,
          thumbnailUrl: withHls.thumbnailUrl,
          publishedAt: withHls.publishedAt,
          formats: withMuxed.formats,
          hlsUrl: withHls.hlsUrl,
          dashUrl: withHls.dashUrl ?? withMuxed.dashUrl,
          likeCount: withHls.likeCount,
          isLive: withHls.isLive,
        );
      }
      // attach progressive formats if missing
      if (withMuxed != null && withHls.bestMuxedUrl == null) {
        return VideoDetails(
          id: withHls.id.isNotEmpty ? withHls.id : withMuxed.id,
          title: withHls.title.isNotEmpty ? withHls.title : withMuxed.title,
          description: withHls.description.isNotEmpty
              ? withHls.description
              : withMuxed.description,
          channelName: withHls.channelName.isNotEmpty
              ? withHls.channelName
              : withMuxed.channelName,
          channelId: withHls.channelId.isNotEmpty
              ? withHls.channelId
              : withMuxed.channelId,
          viewCount: withHls.viewCount > 0 ? withHls.viewCount : withMuxed.viewCount,
          duration: withHls.duration != Duration.zero
              ? withHls.duration
              : withMuxed.duration,
          thumbnailUrl: withHls.thumbnailUrl.isNotEmpty
              ? withHls.thumbnailUrl
              : withMuxed.thumbnailUrl,
          publishedAt: withHls.publishedAt.isNotEmpty
              ? withHls.publishedAt
              : withMuxed.publishedAt,
          formats: [
            ...withHls.formats,
            ...withMuxed.formats,
          ],
          hlsUrl: withHls.hlsUrl,
          dashUrl: withHls.dashUrl ?? withMuxed.dashUrl,
          isLive: withHls.isLive || withMuxed.isLive,
        );
      }
      return withHls;
    }
    if (withMuxed != null) return withMuxed;
    if (any != null) return any;
    throw Exception('Could not load stream: $lastError');
  }

  Future<VideoDetails> _fetchPlayer(
    String videoId,
    Map<String, dynamic> clientCfg,
  ) async {
    final ua = clientCfg['userAgent'] as String?;
    final client = Map<String, dynamic>.from(clientCfg)..remove('userAgent');

    final body = {
      'videoId': videoId,
      'context': {
        'client': client,
        'thirdParty': {
          'embedUrl': 'https://www.youtube.com',
        },
      },
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
          'signatureTimestamp': 20073,
        }
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    };

    // For embedded TV client
    if (client['clientName'] == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
      body['context'] = {
        'client': client,
        'thirdParty': {'embedUrl': 'https://www.youtube.com'},
      };
    }

    final response = await _post('player', body, userAgent: ua);
    final status = response['playabilityStatus']?['status'];
    if (status != null && status != 'OK') {
      final reason = response['playabilityStatus']?['reason'] ?? status;
      throw Exception('Unplayable: $reason');
    }
    return _parseVideoDetails(response, videoId);
  }

  Future<List<Video>> getRelatedVideos(String videoId) async {
    try {
      final response = await _post('next', {
        'videoId': videoId,
        'context': _webContext,
      });
      return _parseRelated(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<Comment>> getComments(String videoId) async {
    try {
      final response = await _post('next', {
        'videoId': videoId,
        'context': _webContext,
      });
      return _parseComments(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<SponsorSegment>> getSponsorSegments(String videoId) async {
    try {
      final uri = Uri.parse(
        'https://sponsor.ajay.app/api/skipSegments?videoID=$videoId'
        '&categories=["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]',
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
      final res = await _http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['dislikes'] as int?;
    } catch (_) {
      return null;
    }
  }

  // ---------- Parsers ----------

  VideoDetails _parseVideoDetails(Map<String, dynamic> response, String videoId) {
    final vd = response['videoDetails'] as Map<String, dynamic>? ?? {};
    final sd = response['streamingData'] as Map<String, dynamic>? ?? {};
    final micro = response['microformat']?['playerMicroformatRenderer']
        as Map<String, dynamic>?;

    final formats = <dynamic>[
      ...(sd['formats'] as List<dynamic>? ?? const []),
      ...(sd['adaptiveFormats'] as List<dynamic>? ?? const []),
    ];

    final thumbs = vd['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
    final thumb = thumbs.isNotEmpty
        ? (thumbs.last['url']?.toString() ?? '')
        : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

    return VideoDetails(
      id: vd['videoId']?.toString() ?? videoId,
      title: vd['title']?.toString() ?? '',
      description: vd['shortDescription']?.toString() ?? '',
      channelName: vd['author']?.toString() ?? '',
      channelId: vd['channelId']?.toString() ?? '',
      viewCount: int.tryParse(vd['viewCount']?.toString() ?? '0') ?? 0,
      duration: Duration(seconds: int.tryParse(vd['lengthSeconds']?.toString() ?? '0') ?? 0),
      thumbnailUrl: thumb.startsWith('//') ? 'https:$thumb' : thumb,
      publishedAt: micro?['publishDate']?.toString() ?? '',
      formats: _parseFormats(formats),
      hlsUrl: sd['hlsManifestUrl']?.toString(),
      dashUrl: sd['dashManifestUrl']?.toString(),
      isLive: vd['isLiveContent'] == true,
    );
  }

  List<VideoFormat> _parseFormats(List<dynamic> formats) {
    final out = <VideoFormat>[];
    for (final f in formats) {
      if (f is! Map) continue;
      // Prefer plain url; skip ciphered (no n-sig solver in pure dart easily)
      String url = f['url']?.toString() ?? '';
      if (url.isEmpty) continue; // skip signatureCipher formats

      final mime = f['mimeType']?.toString() ?? '';
      final hasVideo = mime.contains('video');
      final hasAudio = mime.contains('audio') ||
          (f['audioQuality'] != null) ||
          (hasVideo && f['audioChannels'] != null);
      final codecs = mime.toLowerCase();
      // Progressive/muxed: video mime that also lists audio codec (mp4a / opus)
      final muxedLikely = hasVideo &&
          (codecs.contains('mp4a') ||
              codecs.contains('opus') ||
              (f['audioQuality'] != null && f['width'] != null));
      final isAudioOnly = codecs.startsWith('audio/') || (hasAudio && !hasVideo);
      final isVideoOnly = hasVideo && !muxedLikely && !isAudioOnly;

      out.add(VideoFormat(
        url: url,
        quality: f['qualityLabel']?.toString() ?? f['quality']?.toString() ?? 'Unknown',
        mimeType: mime,
        width: f['width'] as int? ?? 0,
        height: f['height'] as int? ?? 0,
        bitrate: f['bitrate'] as int? ?? 0,
        itag: f['itag'] as int? ?? 0,
        isVideoOnly: isVideoOnly,
        isAudioOnly: isAudioOnly,
        hasAudio: isAudioOnly || muxedLikely || f['audioQuality'] != null,
        hasVideo: hasVideo,
      ));
    }
    return out;
  }

  List<Video> _parseRichGrid(Map<String, dynamic> response) {
    final videos = <Video>[];
    void walk(dynamic node) {
      if (node is Map) {
        if (node['videoRenderer'] != null) {
          final v = _extractVideo(node['videoRenderer']);
          if (v != null) videos.add(v);
        }
        if (node['compactVideoRenderer'] != null) {
          videos.add(_extractCompact(node['compactVideoRenderer']));
        }
        if (node['gridVideoRenderer'] != null) {
          final v = _extractVideo(node['gridVideoRenderer']);
          if (v != null) videos.add(v);
        }
        if (node['richItemRenderer'] != null) {
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

    walk(response['contents']);
    // dedupe
    final seen = <String>{};
    return videos.where((v) => v.id.isNotEmpty && seen.add(v.id)).toList();
  }

  SearchResult _parseSearch(Map<String, dynamic> response) {
    final videos = <Video>[];
    String? continuation;

    void walk(dynamic node) {
      if (node is Map) {
        if (node['videoRenderer'] != null) {
          final v = _extractVideo(node['videoRenderer']);
          if (v != null) videos.add(v);
        }
        if (node['continuationItemRenderer'] != null) {
          continuation ??= node['continuationItemRenderer']['continuationEndpoint']
              ?['continuationCommand']?['token'];
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

    walk(response['contents'] ?? response['onResponseReceivedCommands']);
    final seen = <String>{};
    return SearchResult(
      videos: videos.where((v) => v.id.isNotEmpty && seen.add(v.id)).toList(),
      continuation: continuation,
    );
  }

  List<Video> _parseRelated(Map<String, dynamic> response) {
    final videos = <Video>[];
    void walk(dynamic node) {
      if (node is Map) {
        if (node['compactVideoRenderer'] != null) {
          videos.add(_extractCompact(node['compactVideoRenderer']));
        }
        if (node['lockupViewModel'] != null) {
          // new UI - skip for now
        }
        if (node['videoRenderer'] != null) {
          final v = _extractVideo(node['videoRenderer']);
          if (v != null) videos.add(v);
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

  List<Comment> _parseComments(Map<String, dynamic> response) {
    final comments = <Comment>[];
    void walk(dynamic node) {
      if (node is Map) {
        final cr = node['commentRenderer'] ??
            node['commentThreadRenderer']?['comment']?['commentRenderer'];
        if (cr != null) {
          comments.add(Comment(
            id: cr['commentId']?.toString() ?? '',
            author: _text(cr['authorText']),
            authorAvatar:
                (cr['authorThumbnail']?['thumbnails'] as List?)?.last?['url']?.toString() ??
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

    String channelId = '';
    try {
      channelId = r['ownerText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']
              ?['browseId']
              ?.toString() ??
          r['shortBylineText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']
              ?['browseId']
              ?.toString() ??
          '';
    } catch (_) {}

    String avatar = '';
    try {
      final ch = r['channelThumbnailSupportedRenderers']
              ?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails']
          as List?;
      if (ch != null && ch.isNotEmpty) avatar = ch.last['url']?.toString() ?? '';
    } catch (_) {}

    return Video(
      id: id,
      title: _text(r['title']),
      thumbnailUrl: thumb.isEmpty ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : thumb,
      channelName: _text(r['ownerText']).isNotEmpty
          ? _text(r['ownerText'])
          : _text(r['shortBylineText']),
      channelId: channelId,
      channelAvatar: avatar,
      viewCount: _parseCount(_text(r['viewCountText']).isNotEmpty
          ? _text(r['viewCountText'])
          : _text(r['shortViewCountText'])),
      duration: _parseDurationText(_text(r['lengthText'])),
      publishedAt: _text(r['publishedTimeText']),
      description: _text(r['descriptionSnippet']),
    );
  }

  Video _extractCompact(Map<String, dynamic> r) {
    final id = r['videoId']?.toString() ?? '';
    final thumbs = r['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
    var thumb = thumbs.isNotEmpty ? thumbs.last['url']?.toString() ?? '' : '';
    if (thumb.startsWith('//')) thumb = 'https:$thumb';
    return Video(
      id: id,
      title: _text(r['title']),
      thumbnailUrl: thumb.isEmpty && id.isNotEmpty
          ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
          : thumb,
      channelName: _text(r['shortBylineText']),
      viewCount: _parseCount(_text(r['viewCountText'])),
      duration: _parseDurationText(_text(r['lengthText'])),
      publishedAt: _text(r['publishedTimeText']),
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
    if (m == null) return int.tryParse(cleaned.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    final n = double.tryParse(m.group(1)!) ?? 0;
    final u = (m.group(2) ?? '').toUpperCase();
    switch (u) {
      case 'K':
        return (n * 1e3).round();
      case 'M':
        return (n * 1e6).round();
      case 'B':
        return (n * 1e9).round();
      case 'T':
        return (n * 1e12).round();
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
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      }
    } catch (_) {}
    return Duration.zero;
  }

  void dispose() => _http.close();
}
