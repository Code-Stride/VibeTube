import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/models/video.dart';

void main() {
  group('Video model', () {
    test('formattedViewCount formats billions correctly', () {
      const v = Video(id: 'test123456', title: 'Test', viewCount: 1500000000);
      expect(v.formattedViewCount, '1.5B');
    });

    test('formattedViewCount formats millions correctly', () {
      const v = Video(id: 'test123456', title: 'Test', viewCount: 2300000);
      expect(v.formattedViewCount, '2.3M');
    });

    test('formattedViewCount formats thousands correctly', () {
      const v = Video(id: 'test123456', title: 'Test', viewCount: 45600);
      expect(v.formattedViewCount, '45.6K');
    });

    test('formattedViewCount returns raw number for small counts', () {
      const v = Video(id: 'test123456', title: 'Test', viewCount: 999);
      expect(v.formattedViewCount, '999');
    });

    test('formattedDuration formats hours correctly', () {
      const v = Video(
          id: 'test123456',
          title: 'Test',
          duration: Duration(hours: 1, minutes: 5, seconds: 3));
      expect(v.formattedDuration, '1:05:03');
    });

    test('formattedDuration formats minutes correctly', () {
      const v = Video(
          id: 'test123456',
          title: 'Test',
          duration: Duration(minutes: 3, seconds: 45));
      expect(v.formattedDuration, '3:45');
    });

    test('formattedDuration returns empty for zero duration', () {
      const v = Video(id: 'test123456', title: 'Test');
      expect(v.formattedDuration, '');
    });

    test('toJson and fromJson roundtrip preserves data', () {
      const original = Video(
        id: 'abc12345678',
        title: 'Test Video',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        channelName: 'TestChannel',
        viewCount: 12345,
        duration: Duration(seconds: 300),
        isLive: false,
        isShort: true,
      );
      final json = original.toJson();
      final restored = Video.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.channelName, original.channelName);
      expect(restored.viewCount, original.viewCount);
      expect(restored.duration, original.duration);
      expect(restored.isShort, original.isShort);
    });

    test('copyWith overrides specified fields only', () {
      const original = Video(
        id: 'abc12345678',
        title: 'Original',
        channelName: 'Channel',
        viewCount: 100,
      );
      final modified = original.copyWith(title: 'Modified', viewCount: 200);
      expect(modified.title, 'Modified');
      expect(modified.viewCount, 200);
      expect(modified.channelName, 'Channel'); // unchanged
      expect(modified.id, 'abc12345678'); // unchanged
    });
  });

  group('VideoFormat', () {
    test('isMuxed correctly identifies muxed streams', () {
      const f = VideoFormat(
        url: 'https://example.com/video.mp4',
        quality: '720p',
        hasVideo: true,
        hasAudio: true,
        isAudioOnly: false,
        isVideoOnly: false,
      );
      expect(f.isMuxed, true);
    });

    test('isMuxed returns false for video-only', () {
      const f = VideoFormat(
        url: 'https://example.com/video.mp4',
        quality: '720p',
        hasVideo: true,
        hasAudio: false,
        isAudioOnly: false,
        isVideoOnly: true,
      );
      expect(f.isMuxed, false);
    });

    test('isMuxed returns false for audio-only', () {
      const f = VideoFormat(
        url: 'https://example.com/audio.m4a',
        quality: '128kbps',
        hasVideo: false,
        hasAudio: true,
        isAudioOnly: true,
        isVideoOnly: false,
      );
      expect(f.isMuxed, false);
    });

    test('isMuxed returns false for empty URL', () {
      const f = VideoFormat(
        url: '',
        quality: '720p',
        hasVideo: true,
        hasAudio: true,
        isAudioOnly: false,
        isVideoOnly: false,
      );
      expect(f.isMuxed, false);
    });
  });

  group('VideoDetails', () {
    test('bestMuxedUrl picks highest progressive by height', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        progressiveByHeight: {
          360: 'https://example.com/360.mp4',
          720: 'https://example.com/720.mp4',
          480: 'https://example.com/480.mp4',
        },
      );
      expect(details.bestMuxedUrl, 'https://example.com/720.mp4');
    });

    test('preferredPlayUrl prefers HLS over progressive', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        hlsUrl: 'https://example.com/master.m3u8',
        progressiveByHeight: {720: 'https://example.com/720.mp4'},
      );
      expect(details.preferredPlayUrl, 'https://example.com/master.m3u8');
    });

    test('urlForQuality returns exact HLS variant', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        hlsVariants: {
          720: 'https://example.com/720.m3u8',
          1080: 'https://example.com/1080.m3u8',
        },
      );
      expect(details.urlForQuality('720p'), 'https://example.com/720.m3u8');
    });

    test('availableQualities returns sorted quality labels', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        hlsVariants: {
          360: 'a',
          720: 'b',
          1080: 'c',
        },
      );
      final qs = details.availableQualities;
      expect(qs.first, 'Auto (HLS)');
      expect(qs.last, 'Audio Only');
      expect(qs.contains('1080p'), true);
      expect(qs.contains('720p'), true);
      expect(qs.contains('360p'), true);
    });
  });
}
