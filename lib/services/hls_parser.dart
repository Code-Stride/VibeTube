import 'package:http/http.dart' as http;

class HlsVariant {
  final int width;
  final int height;
  final int bandwidth;
  final String url;
  final String codecs;

  const HlsVariant({
    required this.width,
    required this.height,
    required this.bandwidth,
    required this.url,
    this.codecs = '',
  });

  String get label {
    if (height >= 2160) return '2160p';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    if (height >= 240) return '240p';
    if (height >= 144) return '144p';
    return '${height}p';
  }
}

/// Parses YouTube HLS master playlists into per-resolution variant URLs.
class HlsParser {
  static http.Client? _httpClient;
  static http.Client get _http => _httpClient ??= http.Client();

  /// Dispose the shared HTTP client to free sockets. Call when app is shutting down.
  static void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }

  static Future<List<HlsVariant>> parseMaster(
    String masterUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _http
          .get(
            Uri.parse(masterUrl),
            headers: headers ??
                const {
                  'User-Agent':
                      'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
                  'Accept': '*/*',
                },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return [];
      return parseMasterBody(res.body, masterUrl);
    } catch (_) {
      return [];
    }
  }

  static List<HlsVariant> parseMasterBody(String body, String masterUrl) {
    final base = Uri.parse(masterUrl);
    final lines = body.split(RegExp(r'\r?\n'));
    final out = <HlsVariant>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

      final attrs = _parseAttrs(line.substring('#EXT-X-STREAM-INF:'.length));
      final res = attrs['RESOLUTION'] ?? '';
      final parts = res.split('x');
      final width = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
      final height = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      final bw = int.tryParse(attrs['BANDWIDTH'] ?? '0') ?? 0;
      final codecs = attrs['CODECS'] ?? '';

      // Prefer AVC (avc1) over VP9/AV1 for wider Android ExoPlayer support
      // We'll still keep all; selection logic prefers avc1 later.

      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        if (next.startsWith('#')) break;
        uri = next;
        break;
      }
      if (uri == null || uri.isEmpty || height <= 0) continue;

      final absolute = uri.startsWith('http')
          ? uri
          : base.resolve(uri).toString();

      out.add(HlsVariant(
        width: width,
        height: height,
        bandwidth: bw,
        url: absolute,
        codecs: codecs.replaceAll('"', ''),
      ));
    }

    // Dedupe by height: keep best (prefer avc1, then higher bandwidth)
    final byHeight = <int, HlsVariant>{};
    for (final v in out) {
      final existing = byHeight[v.height];
      if (existing == null) {
        byHeight[v.height] = v;
        continue;
      }
      final preferNew = _score(v) > _score(existing);
      if (preferNew) byHeight[v.height] = v;
    }

    // Sort by height DESCENDING (highest quality first)
    final list = byHeight.values.toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    return list;
  }

  static int _score(HlsVariant v) {
    var s = v.bandwidth;
    final c = v.codecs.toLowerCase();
    if (c.contains('avc1')) s += 50000000; // strongly prefer H.264
    if (c.contains('mp4a')) s += 1000000;
    if (c.contains('vp09') || c.contains('vp9')) s += 100000;
    if (c.contains('av01')) s += 50000;
    return s;
  }

  static Map<String, String> _parseAttrs(String s) {
    final map = <String, String>{};
    // BANDWIDTH=123,RESOLUTION=1280x720,CODECS="avc1...,mp4a..."
    final re = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|[^,]*)');
    for (final m in re.allMatches(s)) {
      final key = m.group(1)!;
      final raw = m.group(2) ?? '';
      final val = raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1)
          : raw;
      map[key] = val;
    }
    return map;
  }
}
