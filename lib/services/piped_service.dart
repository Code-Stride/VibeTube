import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Piped API proxy — returns direct playable stream URLs that bypass
/// YouTube's signatureCipher requirement. Used as primary fallback when
/// InnerTube direct URLs fail.
class PipedService {
  static const List<String> _instances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://piped-api.lunar.icu',
    'https://api.piped.projectsegfault.com',
  ];

  static final http.Client _http = http.Client();

  /// Get direct stream info for a video. Returns best muxed stream URL.
  static Future<PipedStreamInfo?> getStreams(String videoId) async {
    for (final instance in _instances) {
      try {
        final uri = Uri.parse('$instance/streams/$videoId');
        final res = await _http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'VibeTube/1.7',
        }).timeout(const Duration(seconds: 12));

        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        final title = data['title']?.toString() ?? '';
        final uploader = data['uploader']?.toString() ?? '';
        final thumbnail = data['thumbnailUrl']?.toString() ?? data['thumbnail']?.toString() ?? '';
        final duration = (data['duration'] as num?)?.toInt() ?? 0;
        final views = (data['views'] as num?)?.toInt() ?? 0;
        final uploadDate = data['uploadDate']?.toString() ?? '';
        final description = data['description']?.toString() ?? '';

        // Get video streams (prefer muxed)
        final videoStreams = (data['videoStreams'] as List<dynamic>?) ?? [];
        final audioStreams = (data['audioStreams'] as List<dynamic>?) ?? [];
        final hlsUrl = data['hls']?.toString();

        // Find best muxed stream (has both video and audio)
        String? bestUrl;
        int bestHeight = 0;
        String bestQuality = '360p';

        for (final stream in videoStreams) {
          if (stream is! Map) continue;
          final videoOnly = stream['videoOnly'] == true;
          final url = stream['url']?.toString() ?? '';
          if (url.isEmpty || videoOnly) continue;

          final height = stream['height'] as int? ?? 0;
          final quality = stream['quality']?.toString() ?? '';
          if (height > bestHeight) {
            bestHeight = height;
            bestUrl = url;
            bestQuality = quality;
          }
        }

        // If no muxed stream found, try HLS
        if (bestUrl == null && hlsUrl != null && hlsUrl.isNotEmpty) {
          bestUrl = hlsUrl;
          bestQuality = 'HLS';
        }

        // Build quality map for all available streams
        final Map<int, String> qualityMap = {};
        for (final stream in videoStreams) {
          if (stream is! Map) continue;
          final videoOnly = stream['videoOnly'] == true;
          final url = stream['url']?.toString() ?? '';
          if (url.isEmpty || videoOnly) continue;
          final height = stream['height'] as int? ?? 0;
          if (height > 0) {
            qualityMap[height] = url;
          }
        }

        debugPrint('Piped: found ${videoStreams.length} streams for $videoId via $instance');

        return PipedStreamInfo(
          videoId: videoId,
          title: title,
          channelName: uploader,
          thumbnailUrl: thumbnail,
          duration: duration,
          viewCount: views,
          publishedAt: uploadDate,
          description: description,
          bestStreamUrl: bestUrl,
          bestQuality: bestQuality,
          bestHeight: bestHeight,
          hlsUrl: hlsUrl,
          qualityMap: qualityMap,
          audioStreams: audioStreams.whereType<Map>().map((s) => s['url']?.toString() ?? '').where((u) => u.isNotEmpty).toList(),
        );
      } catch (e) {
        debugPrint('Piped instance $instance failed: $e');
        continue;
      }
    }
    return null;
  }

  static void dispose() {
    _http.close();
  }
}

class PipedStreamInfo {
  final String videoId;
  final String title;
  final String channelName;
  final String thumbnailUrl;
  final int duration;
  final int viewCount;
  final String publishedAt;
  final String description;
  final String? bestStreamUrl;
  final String bestQuality;
  final int bestHeight;
  final String? hlsUrl;
  final Map<int, String> qualityMap;
  final List<String> audioStreams;

  const PipedStreamInfo({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.thumbnailUrl,
    required this.duration,
    required this.viewCount,
    required this.publishedAt,
    required this.description,
    this.bestStreamUrl,
    required this.bestQuality,
    required this.bestHeight,
    this.hlsUrl,
    required this.qualityMap,
    required this.audioStreams,
  });
}
