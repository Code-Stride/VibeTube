import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/video.dart';

/// A locally served, single-quality DASH presentation.
///
/// YouTube normally exposes 1080p and above as a silent video stream plus a
/// separate audio stream. A DASH manifest lets Android's ExoPlayer join and
/// synchronize those two streams while the Flutter UI continues to use one
/// VideoPlayerController.
class DashPlaybackSource {
  final Uri uri;
  final String userAgent;
  final int height;
  final String videoCodec;

  const DashPlaybackSource({
    required this.uri,
    required this.userAgent,
    required this.height,
    required this.videoCodec,
  });
}

class DashFormatPair {
  final VideoFormat video;
  final VideoFormat audio;

  const DashFormatPair(this.video, this.audio);
}

/// Builds tiny on-demand MPDs and exposes them on the app's loopback address.
/// Media bytes are still downloaded directly from googlevideo; localhost only
/// serves the XML that tells ExoPlayer which video and audio tracks belong
/// together.
class DashManifestService {
  static HttpServer? _server;
  static StreamSubscription<HttpRequest>? _subscription;
  static final Map<String, String> _manifests = <String, String>{};
  static int _nextId = 0;
  static const int _maxCachedManifests = 24;

  /// Returns decoder alternatives for the requested height, best first.
  /// Every pair comes from the same InnerTube client so its playback headers
  /// remain valid for both URLs.
  static List<DashFormatPair> selectPairs(
    VideoDetails details,
    int targetHeight,
  ) {
    if (targetHeight <= 0) return const <DashFormatPair>[];
    const tolerance = 20;
    final videos =
        details.formats
            .where(
              (f) =>
                  f.isVideoOnly &&
                  f.canUseInDashManifest &&
                  (f.height - targetHeight).abs() <= tolerance,
            )
            .toList()
          ..sort((a, b) {
            final codec = _videoCodecScore(
              b,
              targetHeight,
            ).compareTo(_videoCodecScore(a, targetHeight));
            if (codec != 0) return codec;
            return b.bitrate.compareTo(a.bitrate);
          });

    final pairs = <DashFormatPair>[];
    final signatures = <String>{};
    for (final video in videos) {
      final audios =
          details.formats
              .where(
                (f) =>
                    f.isAudioOnly &&
                    f.canUseInDashManifest &&
                    f.clientUserAgent == video.clientUserAgent,
              )
              .toList()
            ..sort((a, b) {
              final codec = _audioCodecScore(b).compareTo(_audioCodecScore(a));
              if (codec != 0) return codec;
              return b.bitrate.compareTo(a.bitrate);
            });
      if (audios.isEmpty) continue;

      final audio = audios.first;
      final signature = <String>[
        video.containerMimeType,
        video.codecs,
        audio.containerMimeType,
        audio.codecs,
        video.clientUserAgent,
      ].join('|');
      if (signatures.add(signature)) pairs.add(DashFormatPair(video, audio));
    }
    return pairs;
  }

  /// Creates loopback MPD URLs for all useful decoder alternatives.
  static Future<List<DashPlaybackSource>> createSources(
    VideoDetails details,
    int targetHeight,
  ) async {
    final pairs = selectPairs(details, targetHeight);
    if (pairs.isEmpty) return const <DashPlaybackSource>[];
    final server = await _ensureServer();
    final result = <DashPlaybackSource>[];
    for (final pair in pairs) {
      final id = '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
      final path = '/vibetube-dash/$id/stream.mpd';
      _manifests[path] = buildManifest(details, pair.video, pair.audio);
      result.add(
        DashPlaybackSource(
          uri: Uri(
            scheme: 'http',
            host: InternetAddress.loopbackIPv4.address,
            port: server.port,
            path: path,
          ),
          userAgent: pair.video.clientUserAgent,
          height: pair.video.height,
          videoCodec: pair.video.codecs,
        ),
      );
    }
    _trimCache();
    return result;
  }

  static String buildManifest(
    VideoDetails details,
    VideoFormat video,
    VideoFormat audio,
  ) {
    if (!video.canUseInDashManifest || !audio.canUseInDashManifest) {
      throw ArgumentError('DASH formats require initRange and indexRange');
    }
    final durationMs = details.duration.inMilliseconds > 0
        ? details.duration.inMilliseconds
        : (video.approxDurationMs > audio.approxDurationMs
              ? video.approxDurationMs
              : audio.approxDurationMs);
    final duration = _isoDuration(durationMs <= 0 ? 1 : durationMs);
    final videoMime = video.containerMimeType.isEmpty
        ? 'video/mp4'
        : video.containerMimeType;
    final audioMime = audio.containerMimeType.isEmpty
        ? 'audio/mp4'
        : audio.containerMimeType;
    final videoCodec = _xml(video.codecs);
    final audioCodec = _xml(audio.codecs);
    final frameRate = video.fps > 0 ? ' frameRate="${video.fps}"' : '';
    final sampleRate = audio.audioSampleRate > 0
        ? ' audioSamplingRate="${audio.audioSampleRate}"'
        : '';
    final channels = audio.audioChannels > 0 ? audio.audioChannels : 2;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" minBufferTime="PT1.5S" mediaPresentationDuration="$duration">
  <Period id="0" start="PT0S" duration="$duration">
    <AdaptationSet id="0" contentType="video" mimeType="${_xml(videoMime)}" segmentAlignment="true" startWithSAP="1">
      <Representation id="v${video.itag}" bandwidth="${video.bitrate}" codecs="$videoCodec" width="${video.width}" height="${video.height}"$frameRate>
        <BaseURL>${_xml(video.url)}</BaseURL>
        <SegmentBase indexRange="${video.indexRangeStart}-${video.indexRangeEnd}" indexRangeExact="true">
          <Initialization range="${video.initRangeStart}-${video.initRangeEnd}"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
    <AdaptationSet id="1" contentType="audio" mimeType="${_xml(audioMime)}" segmentAlignment="true" startWithSAP="1" lang="und">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="main"/>
      <Representation id="a${audio.itag}" bandwidth="${audio.bitrate}" codecs="$audioCodec"$sampleRate>
        <AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="$channels"/>
        <BaseURL>${_xml(audio.url)}</BaseURL>
        <SegmentBase indexRange="${audio.indexRangeStart}-${audio.indexRangeEnd}" indexRangeExact="true">
          <Initialization range="${audio.initRangeStart}-${audio.initRangeEnd}"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';
  }

  static Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _subscription = server.listen((request) async {
      final body = _manifests[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers
        ..contentType = ContentType('application', 'dash+xml', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set(HttpHeaders.accessControlAllowOriginHeader, '*');
      request.response.write(body);
      await request.response.close();
    });
    return server;
  }

  static void _trimCache() {
    while (_manifests.length > _maxCachedManifests) {
      _manifests.remove(_manifests.keys.first);
    }
  }

  static int _videoCodecScore(VideoFormat f, int targetHeight) {
    final codec = f.codecs.toLowerCase();
    final highResolution = targetHeight > 1080;
    if (codec.contains('vp09') || codec.contains('vp9')) {
      return highResolution ? 500 : 400;
    }
    if (codec.contains('avc1') || codec.contains('avc3')) {
      return highResolution ? 400 : 500;
    }
    if (codec.contains('hev1') || codec.contains('hvc1')) return 350;
    if (codec.contains('av01')) return highResolution ? 300 : 250;
    return 100;
  }

  static int _audioCodecScore(VideoFormat f) {
    final codec = f.codecs.toLowerCase();
    if (codec.contains('mp4a')) return 500;
    if (codec.contains('opus')) return 400;
    if (codec.contains('vorbis')) return 300;
    return 100;
  }

  static String _isoDuration(int milliseconds) {
    final seconds = milliseconds / 1000;
    return 'PT${seconds.toStringAsFixed(3)}S';
  }

  static String _xml(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  static Future<void> dispose() async {
    _manifests.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }
}
