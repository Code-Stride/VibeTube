import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/services/dash_manifest_service.dart';

const _ua = 'com.google.android.youtube/test';

VideoFormat dashVideo({int height = 2160, String ua = _ua}) => VideoFormat(
  url: 'https://video.example/playback?id=video&expire=1',
  quality: '${height}p',
  mimeType: 'video/webm; codecs="vp9"',
  width: height == 4320 ? 7680 : 3840,
  height: height,
  bitrate: 12000000,
  itag: height == 4320 ? 272 : 313,
  isVideoOnly: true,
  hasVideo: true,
  clientUserAgent: ua,
  initRangeStart: 0,
  initRangeEnd: 219,
  indexRangeStart: 220,
  indexRangeEnd: 1777,
  contentLength: 999999,
  approxDurationMs: 60000,
  fps: 60,
);

VideoFormat dashAudio({String ua = _ua}) => VideoFormat(
  url: 'https://audio.example/playback?id=audio&expire=1',
  quality: 'AUDIO_QUALITY_MEDIUM',
  mimeType: 'audio/mp4; codecs="mp4a.40.2"',
  bitrate: 128000,
  itag: 140,
  isAudioOnly: true,
  hasAudio: true,
  clientUserAgent: ua,
  initRangeStart: 0,
  initRangeEnd: 699,
  indexRangeStart: 700,
  indexRangeEnd: 1051,
  contentLength: 100000,
  approxDurationMs: 60000,
  audioSampleRate: 44100,
  audioChannels: 2,
);

void main() {
  group('separate-track DASH quality', () {
    test('4K and 8K become selectable only when matching audio exists', () {
      final details = VideoDetails(
        id: 'abcdefghijk',
        title: 'High resolution',
        formats: [dashVideo(), dashVideo(height: 4320), dashAudio()],
      );

      expect(details.adaptiveDashHeights, containsAll(<int>[2160, 4320]));
      expect(details.availableQualities, <String>[
        'Auto (HLS)',
        '4320p',
        '2160p',
        'Audio Only',
      ]);
      expect(details.canLockQuality('2160p'), isTrue);
      expect(details.canLockQuality('4320p'), isTrue);
      expect(details.canLockQuality('1080p'), isFalse);
    });

    test('never combines URLs issued to different InnerTube clients', () {
      final details = VideoDetails(
        id: 'abcdefghijk',
        title: 'Mismatched clients',
        formats: [
          dashVideo(),
          dashAudio(ua: 'another-client'),
        ],
      );

      expect(details.adaptiveDashHeights, isEmpty);
      expect(DashManifestService.selectPairs(details, 2160), isEmpty);
    });

    test('generated MPD contains synchronized video and audio tracks', () {
      final video = dashVideo(height: 4320);
      final audio = dashAudio();
      final details = VideoDetails(
        id: 'abcdefghijk',
        title: '8K',
        duration: const Duration(minutes: 1),
        formats: [video, audio],
      );

      final mpd = DashManifestService.buildManifest(details, video, audio);
      expect(mpd, contains('mediaPresentationDuration="PT60.000S"'));
      expect(mpd, contains('contentType="video"'));
      expect(mpd, contains('width="7680" height="4320"'));
      expect(mpd, contains('codecs="vp9"'));
      expect(mpd, contains('contentType="audio"'));
      expect(mpd, contains('codecs="mp4a.40.2"'));
      expect(mpd, contains('id=video&amp;expire=1'));
      expect(mpd, contains('id=audio&amp;expire=1'));
      expect(mpd, contains('indexRange="220-1777"'));
      expect(mpd, contains('Initialization range="0-699"'));
    });
  });
}
