import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/api/innertube_client.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/services/download_service.dart';
import 'package:vibetube/services/hls_parser.dart';
import 'package:vibetube/utils/share_links.dart';

/// Regression tests for the July-2026 deep audit. Each one fails against the
/// previous implementation and names the user-visible symptom.
void main() {
  group('Feed parsing resilience', () {
    // A single malformed renderer used to throw out of _parseVideosDeep and
    // return an empty list, so one bad item blanked the entire feed.
    test('a malformed item does not blank the whole feed', () {
      final response = {
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'aaaaaaaaaaa',
              'title': {'simpleText': 'Good one'},
              // thumbnails as a String instead of a List of maps
              'thumbnail': {'thumbnails': 'not-a-list'},
            }
          },
          {
            'videoRenderer': {
              'videoId': 'bbbbbbbbbbb',
              'title': {'simpleText': 'Another good one'},
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/vi/bbbbbbbbbbb/hq.jpg'}
                ]
              },
            }
          },
        ]
      };

      final videos = InnerTubeClient().parseVideosForTest(response);
      expect(videos.length, 2);
      expect(videos.map((v) => v.id), containsAll(['aaaaaaaaaaa', 'bbbbbbbbbbb']));
      // Falls back to the derived thumbnail rather than throwing.
      expect(videos.first.thumbnailUrl, contains('aaaaaaaaaaa'));
    });

    test('an empty thumbnails list does not throw (StateError on .last)', () {
      final response = {
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'ccccccccccc',
              'title': {'simpleText': 'Empty thumbs'},
              'thumbnail': {'thumbnails': []},
            }
          }
        ]
      };
      final videos = InnerTubeClient().parseVideosForTest(response);
      expect(videos.length, 1);
      expect(videos.single.thumbnailUrl, contains('ccccccccccc'));
    });

    test('one avatar-less comment does not wipe out the thread', () {
      // `(list as List?)?.last` throws StateError when the list is empty,
      // which used to make getComments() return nothing at all.
      final response = {
        'contents': [
          {
            'commentRenderer': {
              'commentId': '1',
              'authorText': {'simpleText': 'No avatar'},
              'contentText': {'runs': [
                {'text': 'first'}
              ]},
              'authorThumbnail': {'thumbnails': []},
            }
          },
          {
            'commentRenderer': {
              'commentId': '2',
              'authorText': {'simpleText': 'Has avatar'},
              'contentText': {'runs': [
                {'text': 'second'}
              ]},
              'authorThumbnail': {'thumbnails': [
                {'url': 'https://example.com/a.jpg'}
              ]},
            }
          },
        ]
      };
      final comments = InnerTubeClient().parseCommentsForTest(response);
      expect(comments.length, 2);
      expect(comments.first.authorAvatar, '');
      expect(comments.last.authorAvatar, 'https://example.com/a.jpg');
    });

    test('a string likeCount does not break the player response', () {
      // YouTube sends this as a String often enough that `as num?` threw and
      // took out the whole client, producing "No playable stream found".
      final details = InnerTubeClient().parseDetailsForTest({
        'videoDetails': {
          'videoId': 'ddddddddddd',
          'title': 'T',
          'author': 'A',
          'lengthSeconds': '120',
          'likeCount': '4321',
          'viewCount': '99',
        }
      }, 'ddddddddddd');
      expect(details.likeCount, 4321);
      expect(details.duration, const Duration(seconds: 120));
    });
  });

  group('Pagination', () {
    test('a continuation token is extracted from a search response', () {
      // SearchResult.continuation was never populated, so "load more"
      // re-requested page 1 and the dedupe filter dropped everything.
      final response = {
        'onResponseReceivedCommands': [
          {
            'appendContinuationItemsAction': {
              'continuationItems': [
                {
                  'continuationItemRenderer': {
                    'continuationEndpoint': {
                      'continuationCommand': {'token': 'TOKEN123'}
                    }
                  }
                }
              ]
            }
          }
        ]
      };
      expect(InnerTubeClient().findContinuationForTest(response), 'TOKEN123');
    });

    test('a response without a token yields null', () {
      expect(
        InnerTubeClient().findContinuationForTest({'contents': []}),
        isNull,
      );
    });
  });

  group('HLS audio renditions', () {
    test('video-only variants are recognised as having no audio', () {
      // Locking to a video-only media playlist plays a silent video: its
      // audio lives in a separate EXT-X-MEDIA group in the master.
      const body = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-0",URI="https://example.com/audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720,CODECS="avc1.4d401f",AUDIO="audio-0"
https://example.com/720-videoonly.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
https://example.com/360-muxed.m3u8
''';
      final variants = HlsParser.parseMasterBody(body, 'https://example.com/m.m3u8');
      final byHeight = {for (final v in variants) v.height: v};

      expect(byHeight[720]!.hasAudio, false);
      expect(byHeight[360]!.hasAudio, true);
    });

    test('an unknown codec string is assumed muxed', () {
      const v = HlsVariant(width: 1280, height: 720, bandwidth: 1, url: 'u');
      expect(v.hasAudio, true);
    });
  });

  group('View count word boundaries', () {
    test("'lac' does not match inside an unrelated word", () {
      // A bare `contains` fired on "black", "place", "palace".
      expect(InnerTubeClient.parseCount('1.2M views'), 1200000);
      expect(InnerTubeClient.parseCount('4.2 lakh views'), 420000);
      // "black" must not be read as 'lac' (would give 100000).
      expect(InnerTubeClient.parseCount('5 black friday deals'), 5);
    });
  });

  group('ShareLinks host matching', () {
    test('look-alike domains are rejected', () {
      // endsWith('youtube.com') also matched attacker-controlled hosts.
      expect(
        ShareLinks.parseVideoId(
            Uri.parse('https://evilyoutube.com/watch?v=dQw4w9WgXcQ')),
        isNull,
      );
      expect(
        ShareLinks.parseVideoId(
            Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
      expect(
        ShareLinks.parseVideoId(
            Uri.parse('https://m.youtube.com/shorts/dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
    });
  });

  group('Download integrity', () {
    test('ISO-BMFF header check still guards non-video payloads', () {
      final good = [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0];
      final html = '<!DOCTYPE ht'.codeUnits;
      expect(DownloadService.hasIsoBmffHeader(good), true);
      expect(DownloadService.hasIsoBmffHeader(html), false);
      expect(DownloadService.hasIsoBmffHeader([1, 2, 3]), false);
    });
  });

  group('Quality resolution', () {
    test('an exact progressive match wins over a nearest HLS match', () {
      const details = VideoDetails(
        id: 'eeeeeeeeeee',
        title: 'T',
        hlsVariants: {1080: 'hls-1080'},
        progressiveByHeight: {360: 'mp4-360'},
      );
      expect(details.urlForQuality('360p'), 'mp4-360');
      expect(details.urlForQuality('1080p'), 'hls-1080');
    });
  });
}
