import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibetube/api/innertube_client.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/services/caption_service.dart';
import 'package:vibetube/services/storage_service.dart';

/// Regression tests for bugs found during the code audit. Each test fails
/// against the previous implementation and documents the user-visible symptom.
void main() {
  group('Caption parsing', () {
    test('parses the default timedtext <text start dur> format', () {
      // This is what YouTube returns unless &fmt=ttml is requested. The parser
      // only understood TTML <p begin end>, so captions were always empty.
      const xml = '<?xml version="1.0" encoding="utf-8"?><transcript>'
          '<text start="0.12" dur="3.4">hello world</text>'
          '<text start="3.6" dur="2">second line</text>'
          '</transcript>';

      final cues = CaptionService.parseCaptions(xml);

      expect(cues.length, 2);
      expect(cues.first.text, 'hello world');
      expect(cues.first.start, const Duration(milliseconds: 120));
      expect(cues.first.end, const Duration(milliseconds: 3520));
      expect(cues.last.text, 'second line');
    });

    test('collapses newlines inside a transcript cue', () {
      const xml = '<transcript><text start="1" dur="2">line\n  two</text></transcript>';
      expect(CaptionService.parseCaptions(xml).single.text, 'line two');
    });

    test('decodes entities without double-decoding ampersands', () {
      const xml = '<transcript><text start="0" dur="1">'
          'rock &amp;amp; roll &amp;#39;90s</text></transcript>';
      expect(CaptionService.parseCaptions(xml).single.text, "rock & roll '90s");
    });

    test('still parses TTML <p begin end> cues', () {
      const xml = '<p begin="00:00:01.000" end="00:00:04.000">ttml cue</p>';
      final cues = CaptionService.parseCaptions(xml);
      expect(cues.single.text, 'ttml cue');
      expect(cues.single.start, const Duration(seconds: 1));
    });

    test('fractional seconds are a fraction, not a millisecond count', () {
      // "00:01:23.4" is 83.4s. Reading ".4" with int.parse produced 4ms, so
      // every subtitle appeared ~400ms early and drifted.
      const xml = '<p begin="00:01:23.4" end="00:01:25.45">drift</p>';
      final cue = CaptionService.parseCaptions(xml).single;
      expect(cue.start, const Duration(minutes: 1, seconds: 23, milliseconds: 400));
      expect(cue.end, const Duration(minutes: 1, seconds: 25, milliseconds: 450));
    });

    test('cues are returned in chronological order', () {
      const xml = '<transcript>'
          '<text start="10" dur="1">later</text>'
          '<text start="2" dur="1">earlier</text>'
          '</transcript>';
      final cues = CaptionService.parseCaptions(xml);
      expect(cues.map((c) => c.text), ['earlier', 'later']);
    });
  });

  group('Player response extraction', () {
    test('survives a "};" inside a nested object', () {
      // The old non-greedy regex stopped at the first "};" and the truncated
      // text failed to decode, silently disabling captions.
      const page = 'var ytInitialPlayerResponse = '
          '{"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":'
          '[{"baseUrl":"https://x/timedtext","languageCode":"en"}]}},'
          '"videoDetails":{"title":"t"}};';

      final json = CaptionService.extractJson(page, 'ytInitialPlayerResponse');

      expect(json, isNotNull);
      expect(json!['captions'], isNotNull);
    });

    test('survives a "};" inside a string value', () {
      const page = r'var ytInitialPlayerResponse = '
          r'{"videoDetails":{"shortDescription":"js: function(){return 1};"},'
          r'"captions":{"ok":true}};';

      final json = CaptionService.extractJson(page, 'ytInitialPlayerResponse');

      expect(json, isNotNull);
      expect((json!['captions'] as Map)['ok'], isTrue);
    });

    test('ignores braces inside escaped strings', () {
      const page = r'var ytInitialPlayerResponse = '
          r'{"a":"quote \" and brace }","b":2};';
      final json = CaptionService.extractJson(page, 'ytInitialPlayerResponse');
      expect(json?['b'], 2);
    });

    test('returns null when the key is absent or the page is truncated', () {
      expect(CaptionService.extractJson('nothing here', 'ytInitialPlayerResponse'), isNull);
      expect(
        CaptionService.extractJson('var ytInitialPlayerResponse = {"a":1', 'ytInitialPlayerResponse'),
        isNull,
      );
    });
  });

  group('View count parsing', () {
    test('handles Indian numbering served with gl=IN', () {
      // The app defaults to region IN, where YouTube localises counts. Without
      // lakh/crore support "4.2 lakh views" parsed as 4 views.
      expect(InnerTubeClient.parseCount('4.2 lakh views'), 420000);
      expect(InnerTubeClient.parseCount('1.5 crore views'), 15000000);
      expect(InnerTubeClient.parseCount('1.5 करोड़ बार देखा गया'), 15000000);
      expect(InnerTubeClient.parseCount('3 लाख views'), 300000);
    });

    test('still handles the western suffixes', () {
      expect(InnerTubeClient.parseCount('1.2M views'), 1200000);
      expect(InnerTubeClient.parseCount('532K views'), 532000);
      expect(InnerTubeClient.parseCount('1,234,567 views'), 1234567);
      expect(InnerTubeClient.parseCount('2.1B views'), 2100000000);
      expect(InnerTubeClient.parseCount('12 views'), 12);
    });

    test('treats text-only labels as zero', () {
      expect(InnerTubeClient.parseCount('No views'), 0);
      expect(InnerTubeClient.parseCount(''), 0);
    });
  });

  group('Duration label parsing', () {
    test('parses hours and minutes labels', () {
      expect(InnerTubeClient.parseDurationText('1:23:45'),
          const Duration(hours: 1, minutes: 23, seconds: 45));
      expect(InnerTubeClient.parseDurationText('12:34'),
          const Duration(minutes: 12, seconds: 34));
    });

    test('survives padding characters instead of returning zero', () {
      expect(InnerTubeClient.parseDurationText('\u200e12:34'),
          const Duration(minutes: 12, seconds: 34));
    });

    test('returns zero for live/unparseable labels', () {
      expect(InnerTubeClient.parseDurationText('LIVE'), Duration.zero);
      expect(InnerTubeClient.parseDurationText(''), Duration.zero);
    });
  });

  group('StorageService concurrency', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('concurrent history writes do not lose entries', () async {
      // Each mutator does load -> edit -> save with awaits in between, so
      // unsynchronised calls read the same stale list and the last write won.
      final storage = StorageService();

      await Future.wait([
        for (var i = 0; i < 10; i++)
          storage.addToHistory(Video(id: 'video$i'.padRight(11, 'x'), title: 'v$i')),
      ]);

      expect((await storage.getHistory()).length, 10);
    });

    test('concurrent downloads are all recorded', () async {
      final storage = StorageService();

      await Future.wait([
        for (var i = 0; i < 8; i++)
          storage.addDownload(Video(id: 'dl$i'.padRight(11, 'y'), title: 'd$i')),
      ]);

      expect((await storage.getDownloads()).length, 8);
    });

    test('a like and a watch-later write do not clobber each other', () async {
      final storage = StorageService();
      const a = Video(id: 'aaaaaaaaaaa', title: 'A');
      const b = Video(id: 'bbbbbbbbbbb', title: 'B');

      await Future.wait([
        storage.toggleLiked(a),
        storage.toggleLiked(b),
        storage.toggleWatchLater(a),
      ]);

      expect((await storage.getLiked()).length, 2);
      expect((await storage.getWatchLater()).length, 1);
    });

    test('history stays capped at 100 under concurrent writes', () async {
      final storage = StorageService();

      await Future.wait([
        for (var i = 0; i < 120; i++)
          storage.addToHistory(Video(id: 'v$i'.padRight(11, 'z'), title: 'v$i')),
      ]);

      expect((await storage.getHistory()).length, 100);
    });
  });
}
