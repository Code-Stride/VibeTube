import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/utils/share_links.dart';

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

  group('Offline download stream selection', () {
    // A manifest saved as .mp4 looks downloaded but never plays, so
    // bestMuxedUrl must never surface one for the download path.
    bool isProgressive(String? u) =>
        u != null &&
        u.isNotEmpty &&
        !u.contains('.m3u8') &&
        !u.contains('/manifest/hls') &&
        !u.contains('/manifest/dash');

    test('progressive muxed URL is accepted', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        progressiveByHeight: {
          360: 'https://example.com/360.mp4',
          720: 'https://example.com/720.mp4',
        },
      );
      expect(details.bestMuxedUrl, 'https://example.com/720.mp4');
      expect(isProgressive(details.bestMuxedUrl), true);
    });

    test('HLS-only video exposes no progressive stream to download', () {
      const details = VideoDetails(
        id: 'test123456',
        title: 'Test',
        hlsUrl: 'https://example.com/master.m3u8',
        hlsVariants: {720: 'https://example.com/720.m3u8'},
      );
      expect(details.bestMuxedUrl, isNull);
      expect(isProgressive(details.preferredPlayUrl), false);
    });

    test('manifest URLs are rejected by the progressive guard', () {
      expect(isProgressive('https://example.com/master.m3u8'), false);
      expect(isProgressive('https://r1.googlevideo.com/manifest/hls/x'), false);
      expect(isProgressive('https://r1.googlevideo.com/manifest/dash/x'), false);
      expect(isProgressive(''), false);
      expect(isProgressive(null), false);
    });
  });

  group('Update version compare', () {
    // Mirrors UpdateService._isNewer, which must ignore build metadata
    // ("1.5.0+11") and a leading "v" so the dialog doesn't loop forever.
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first;
      final cleaned = core.replaceAll(RegExp(r'[^0-9.]'), '');
      final parts = cleaned.split('.');
      return [
        int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
        int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
        int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
      ];
    }

    bool isNewer(String remote, String local) {
      final r = parse(remote);
      final l = parse(local);
      for (var i = 0; i < 3; i++) {
        if (r[i] > l[i]) return true;
        if (r[i] < l[i]) return false;
      }
      return false;
    }

    test('build metadata does not make a version look newer', () {
      expect(isNewer('1.5.0', '1.5.0+11'), false);
      expect(parse('1.5.0+11'), [1, 5, 0]);
    });

    test('detects genuinely newer versions', () {
      expect(isNewer('1.6.0', '1.5.0'), true);
      expect(isNewer('2.0.0', '1.9.9'), true);
      expect(isNewer('1.5.1', '1.5.0'), true);
    });

    test('does not downgrade', () {
      expect(isNewer('1.4.0', '1.5.0'), false);
      expect(isNewer('1.5.0', '1.5.0'), false);
    });

    test('pre-release suffix is ignored', () {
      expect(parse('1.6.0-beta'), [1, 6, 0]);
      expect(isNewer('1.6.0-beta', '1.5.0'), true);
    });
  });

  group('ShareLinks', () {
    const id = 'dQw4w9WgXcQ';

    test('shares a VibeTube link, not a YouTube one', () {
      final link = ShareLinks.watch(id);
      expect(link, contains(ShareLinks.host));
      expect(link, endsWith('/w/$id'));
      expect(link, isNot(contains('youtu')));
    });

    test('share text keeps the title above the link', () {
      final text = ShareLinks.shareText(id, 'Never Gonna Give You Up');
      expect(text, startsWith('Never Gonna Give You Up'));
      expect(text, contains(ShareLinks.watch(id)));
    });

    test('share text is just the link when there is no title', () {
      expect(ShareLinks.shareText(id, '   '), ShareLinks.watch(id));
    });

    test('round-trips its own watch link', () {
      expect(ShareLinks.parseVideoId(Uri.parse(ShareLinks.watch(id))), id);
    });

    test('parses the custom scheme', () {
      expect(ShareLinks.parseVideoId(Uri.parse('vibetube://watch?v=$id')), id);
      // Bare form must go through the string helper: Uri.parse lowercases the
      // authority and would corrupt the id.
      expect(ShareLinks.parseVideoIdFromString('vibetube://$id'), id);
      expect(ShareLinks.parseVideoIdFromString('vibetube://watch?v=$id'), id);
    });

    test('still accepts YouTube links shared from other apps', () {
      for (final u in [
        'https://youtu.be/$id',
        'https://www.youtube.com/watch?v=$id',
        'https://m.youtube.com/watch?v=$id&t=42s',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube.com/live/$id',
      ]) {
        expect(ShareLinks.parseVideoId(Uri.parse(u)), id, reason: u);
      }
    });

    test('rejects malformed or unrelated links', () {
      for (final u in [
        'https://example.com/w/$id',
        'https://youtu.be/tooshort',
        'https://www.youtube.com/watch?v=way_too_long_id_here',
        'https://code-stride.github.io/VibeTube/',
        'https://www.youtube.com/feed/subscriptions',
      ]) {
        expect(ShareLinks.parseVideoId(Uri.parse(u)), isNull, reason: u);
      }
    });

    test('ids with hyphens and underscores survive', () {
      const tricky = 'a-b_c1D2e3F';
      expect(ShareLinks.parseVideoId(Uri.parse(ShareLinks.watch(tricky))),
          tricky);
    });
  });

  group('Quality locking', () {
    // A locked quality must never resolve to a different height. The old
    // candidate list appended every other variant plus the adaptive master,
    // so picking 1080p could quietly play 360p.
    const details = VideoDetails(
      id: 'test123456',
      title: 'Test',
      hlsUrl: 'https://example.com/master.m3u8',
      hlsVariants: {
        360: 'https://example.com/360.m3u8',
        720: 'https://example.com/720.m3u8',
        1080: 'https://example.com/1080.m3u8',
      },
      progressiveByHeight: {
        360: 'https://example.com/360.mp4',
        720: 'https://example.com/720.mp4',
      },
    );

    test('exact HLS variant wins for a locked height', () {
      expect(details.urlForQuality('1080p'), 'https://example.com/1080.m3u8');
      expect(details.urlForQuality('720p'), 'https://example.com/720.m3u8');
      expect(details.urlForQuality('360p'), 'https://example.com/360.m3u8');
    });

    test('Auto resolves to the adaptive master', () {
      // Auto (HLS) = master playlist for adaptive streaming
      expect(details.urlForQuality('Auto (HLS)'), details.hlsUrl);
      // Auto / Best = highest quality variant (not master)
      expect(details.urlForQuality('Auto'), isNot(details.hlsUrl));
      expect(details.urlForQuality('Best'), isNot(details.hlsUrl));
    });

    test('a locked height never resolves to the master playlist', () {
      for (final q in ['360p', '720p', '1080p']) {
        expect(details.urlForQuality(q), isNot(details.hlsUrl), reason: q);
      }
    });

    test('canLockQuality reports what is actually available', () {
      expect(details.canLockQuality('1080p'), isTrue);
      expect(details.canLockQuality('720p'), isTrue);
      expect(details.canLockQuality('Auto (HLS)'), isTrue);
      expect(details.canLockQuality('Audio Only'), isTrue);
    });

    test('progressive-only video still locks by height', () {
      const prog = VideoDetails(
        id: 'test123456',
        title: 'Test',
        progressiveByHeight: {
          360: 'https://example.com/360.mp4',
          720: 'https://example.com/720.mp4',
        },
      );
      expect(prog.urlForQuality('720p'), 'https://example.com/720.mp4');
      expect(prog.urlForQuality('360p'), 'https://example.com/360.mp4');
    });

    test('quality ladder is ordered high to low and bracketed', () {
      final qs = details.availableQualities;
      expect(qs.first, 'Auto (HLS)');
      expect(qs.last, 'Audio Only');
      final mid = qs.sublist(1, qs.length - 1);
      expect(mid, ['1080p', '720p', '360p']);
    });
  });
}
