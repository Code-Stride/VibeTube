import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/api/innertube_client.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/services/update_service.dart';
import 'package:vibetube/utils/text_utils.dart';

/// Regression tests for the deep bug-audit fixes.
///
/// Each group names the behaviour that used to be wrong, so a future change
/// that reintroduces it fails here rather than in someone's hands.
void main() {
  group('Continuation tokens (infinite scroll)', () {
    test('finds the token in a modern continuationItemRenderer', () {
      final response = <String, dynamic>{
        'contents': {
          'items': [
            {'videoRenderer': <String, dynamic>{'videoId': 'aaaaaaaaaaa'}},
            {
              'continuationItemRenderer': {
                'continuationEndpoint': {
                  'continuationCommand': {'token': 'TOKEN_123'},
                },
              },
            },
          ],
        },
      };
      expect(InnerTubeClient.extractContinuation(response), 'TOKEN_123');
    });

    test('falls back to the legacy nextContinuationData shape', () {
      final response = <String, dynamic>{
        'continuations': [
          {
            'nextContinuationData': {'continuation': 'LEGACY_TOKEN'},
          },
        ],
      };
      expect(InnerTubeClient.extractContinuation(response), 'LEGACY_TOKEN');
    });

    test('returns null when there is no next page', () {
      expect(InnerTubeClient.extractContinuation(<String, dynamic>{}), isNull);
      expect(
        InnerTubeClient.extractContinuation(<String, dynamic>{
          'contents': {'items': <dynamic>[]},
        }),
        isNull,
      );
    });
  });

  group('Live badge detection', () {
    test('a title containing "live" is not a live stream', () {
      // The old check stringified the renderer and searched for "LIVE", so
      // "Delivery", "Oliver" and "Live Aid documentary" all got a red badge
      // and were routed down the live-only HLS path.
      final lockup = <String, dynamic>{
        'contentId': 'abcdefghijk',
        'metadata': {
          'title': {'content': 'Fast Delivery Tips'},
        },
      };
      expect(InnerTubeClient.lockupIsLive(lockup), isFalse);
    });

    test('a real live badge is detected', () {
      final lockup = <String, dynamic>{
        'contentId': 'abcdefghijk',
        'badges': [
          {
            'badgeViewModel': {'style': 'BADGE_STYLE_TYPE_LIVE'},
          },
        ],
      };
      expect(InnerTubeClient.lockupIsLive(lockup), isTrue);
    });
  });

  group('Locale-aware view counts', () {
    test('dot-grouped locales are not truncated to a single digit', () {
      expect(InnerTubeClient.parseCount('1.234.567 Aufrufe'), 1234567);
      expect(InnerTubeClient.parseCount('12.345 visualizaciones'), 12345);
    });

    test('comma-decimal locales keep their fraction', () {
      expect(InnerTubeClient.parseCount('1,5 Mio. Aufrufe'), 1500000);
    });

    test('space-grouped locales parse', () {
      expect(InnerTubeClient.parseCount('1 234 567 vues'), 1234567);
    });

    test('the existing English behaviour is unchanged', () {
      expect(InnerTubeClient.parseCount('1,234,567 views'), 1234567);
      expect(InnerTubeClient.parseCount('1.2M views'), 1200000);
      expect(InnerTubeClient.parseCount('532K views'), 532000);
      expect(InnerTubeClient.parseCount('12 views'), 12);
      expect(InnerTubeClient.parseCount('4.2 lakh views'), 420000);
    });

    test('a trailing word is never read as a magnitude suffix', () {
      // "t" inside a following word used to be matched as "trillion".
      expect(InnerTubeClient.parseCount('42 watching'), 42);
    });
  });

  group('Update comparison', () {
    test('a build-number-only bump is offered', () {
      // 1.11.0+27 over 1.11.0+26 compared equal before, so hotfix builds were
      // never surfaced.
      expect(UpdateService.isNewer('1.11.0+27', '1.11.0+26'), isTrue);
      expect(UpdateService.isNewer('1.11.0+26', '1.11.0+26'), isFalse);
      expect(UpdateService.isNewer('1.11.0+25', '1.11.0+26'), isFalse);
    });

    test('semver still dominates the build number', () {
      expect(UpdateService.isNewer('1.12.0', '1.11.0+99'), isTrue);
      expect(UpdateService.isNewer('1.11.0+99', '1.12.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.11.0+26'), isTrue);
    });
  });

  group('Quality locking honesty', () {
    const master = 'https://example.com/master.m3u8';

    test('a master-only playlist cannot lock a specific height', () {
      // Previously any height returned true whenever hlsUrl was set, so the
      // sheet advertised "Tap to lock · HLS" for 2160p on a 360p video.
      const d = VideoDetails(id: 'x', title: 't', hlsUrl: master);
      expect(d.canLockQuality('2160p'), isFalse);
      expect(d.canLockQuality('Auto (HLS)'), isTrue);
      expect(d.canLockQuality('Audio Only'), isTrue);
    });

    test('a parsed variant can lock', () {
      const d = VideoDetails(
        id: 'x',
        title: 't',
        hlsUrl: master,
        hlsVariants: {720: 'https://example.com/720.m3u8'},
      );
      expect(d.canLockQuality('720p'), isTrue);
      expect(d.canLockQuality('2160p'), isFalse);
    });

    test('availableQualities collapses to Auto when nothing is parsed', () {
      const d = VideoDetails(id: 'x', title: 't', hlsUrl: master);
      expect(d.availableQualities, ['Auto (HLS)', 'Audio Only']);
    });
  });

  group('Avatar initials', () {
    test('emoji channel names do not produce a lone surrogate', () {
      // name[0] returns half a surrogate pair, which renders as a tofu box.
      final letter = initialLetter('🎵 Music Channel');
      expect(letter.runes.length, 1);
      expect(letter, '🎵');
    });

    test('plain names still uppercase the first letter', () {
      expect(initialLetter('vibetube'), 'V');
      expect(initialLetter('  spaced'), 'S');
    });

    test('empty names fall back', () {
      expect(initialLetter(''), 'V');
      expect(initialLetter('   ', fallback: '?'), '?');
    });
  });
}
