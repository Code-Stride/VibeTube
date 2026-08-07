import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/api/innertube_client.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/services/hls_parser.dart';
import 'package:vibetube/utils/share_links.dart';

/// Round-three audit regressions. Each test fails against the previous
/// implementation and names the user-visible symptom.
void main() {
  group('Feed parsing survives malformed items', () {
    // _extractVideo had no try/catch (unlike _extractShort / _extractLockup)
    // and indexed thumbs.last['url'] blindly. Running inside the walk()
    // recursion, any throw escaped to the caller's catch and turned the whole
    // response into an empty list: ONE bad item blanked an entire feed.
    test('a videoRenderer with a non-list thumbnail does not kill the page', () {
      final response = {
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'aaaaaaaaaaa',
              'title': {'simpleText': 'Broken'},
              'thumbnail': {'thumbnails': 'not-a-list'},
            },
          },
          {
            'videoRenderer': {
              'videoId': 'bbbbbbbbbbb',
              'title': {'simpleText': 'Good'},
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/vi/bbbbbbbbbbb/hq.jpg'},
                ],
              },
            },
          },
        ],
      };

      final videos = InnerTubeTestHooks.parseVideosDeep(response);

      expect(videos.map((v) => v.id), contains('bbbbbbbbbbb'),
          reason: 'the healthy item must still be returned');
    });

    test('thumbnail entries that are not maps are tolerated', () {
      final response = {
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'ccccccccccc',
              'title': {'simpleText': 'Odd thumbs'},
              'thumbnail': {
                'thumbnails': ['just-a-string'],
              },
            },
          },
        ],
      };

      final videos = InnerTubeTestHooks.parseVideosDeep(response);
      expect(videos.length, 1);
      // Falls back to the derived i.ytimg URL rather than throwing.
      expect(videos.first.thumbnailUrl, contains('ccccccccccc'));
    });
  });

  group('Comment parsing survives a missing avatar', () {
    // `(list as List?)?.last?['url']` looks null-safe but .last throws
    // StateError on an EMPTY list rather than returning null. One comment
    // without an avatar therefore removed every comment on the video.
    test('an empty authorThumbnail list does not drop all comments', () {
      final response = {
        'contents': [
          {
            'commentRenderer': {
              'commentId': 'c1',
              'authorText': {'simpleText': 'No Avatar'},
              'authorThumbnail': {'thumbnails': <dynamic>[]},
              'contentText': {'simpleText': 'first'},
            },
          },
          {
            'commentRenderer': {
              'commentId': 'c2',
              'authorText': {'simpleText': 'Has Avatar'},
              'authorThumbnail': {
                'thumbnails': [
                  {'url': 'https://example.com/a.jpg'},
                ],
              },
              'contentText': {'simpleText': 'second'},
            },
          },
        ],
      };

      final comments = InnerTubeTestHooks.parseCommentsDeep(response);

      expect(comments.length, 2, reason: 'both comments must survive');
      expect(comments.first.authorAvatar, '');
      expect(comments.last.authorAvatar, 'https://example.com/a.jpg');
    });
  });

  group('Auto quality is actually adaptive', () {
    // preferredPlayUrl returned the single highest variant, so "Auto" pinned
    // playback to the top rendition: continuous rebuffering on slow links and
    // no ability to step down. It also skipped the master's separate audio
    // group.
    test('the adaptive master wins over the highest single variant', () {
      const details = VideoDetails(
        id: 'test1234567',
        title: 'Test',
        hlsUrl: 'https://example.com/master.m3u8',
        hlsVariants: {
          1080: 'https://example.com/1080.m3u8',
          2160: 'https://example.com/2160.m3u8',
        },
      );
      expect(details.preferredPlayUrl, 'https://example.com/master.m3u8');
    });

    test('without a master it still falls back to the best variant', () {
      const details = VideoDetails(
        id: 'test1234567',
        title: 'Test',
        hlsVariants: {720: 'https://example.com/720.m3u8'},
      );
      expect(details.preferredPlayUrl, 'https://example.com/720.m3u8');
    });
  });

  group('HLS variants without audio are not lockable', () {
    // YouTube frequently lists video-only renditions and puts audio in a
    // separate #EXT-X-MEDIA group referenced by the AUDIO attribute. Handing
    // such a rendition straight to the player yields video with NO SOUND.
    test('video-only renditions are detected', () {
      const v = HlsVariant(
        width: 1920,
        height: 1080,
        bandwidth: 100,
        url: 'u',
        codecs: 'avc1.640028',
      );
      expect(v.hasAudio, isFalse);
    });

    test('muxed renditions are detected', () {
      const v = HlsVariant(
        width: 1920,
        height: 1080,
        bandwidth: 100,
        url: 'u',
        codecs: 'avc1.4d401e,mp4a.40.2',
      );
      expect(v.hasAudio, isTrue);
    });

    test('opus audio counts', () {
      const v = HlsVariant(
        width: 1280,
        height: 720,
        bandwidth: 100,
        url: 'u',
        codecs: 'vp09.00.10.08,opus',
      );
      expect(v.hasAudio, isTrue);
    });

    test('unknown codecs are assumed playable, not discarded', () {
      const v = HlsVariant(
        width: 1280,
        height: 720,
        bandwidth: 100,
        url: 'u',
      );
      expect(v.hasAudio, isTrue);
    });
  });

  group('Link host matching is exact', () {
    // endsWith('youtube.com') also matches attacker-controlled hosts, letting
    // a hostile link masquerade as a YouTube link inside the app.
    test('lookalike domains are rejected', () {
      expect(
        ShareLinks.parseVideoId(
            Uri.parse('https://evilyoutube.com/watch?v=dQw4w9WgXcQ')),
        isNull,
      );
      expect(
        ShareLinks.parseVideoId(
            Uri.parse('https://notyoutube.com/watch?v=dQw4w9WgXcQ')),
        isNull,
      );
    });

    test('genuine YouTube hosts still resolve', () {
      for (final h in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/shorts/dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
      ]) {
        expect(ShareLinks.parseVideoId(Uri.parse(h)), 'dQw4w9WgXcQ',
            reason: h);
      }
    });
  });
}
