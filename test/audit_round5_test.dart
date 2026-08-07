import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/providers/app_provider.dart';
import 'package:vibetube/providers/mini_player_controller.dart';
import 'package:vibetube/services/storage_service.dart';
import 'package:vibetube/utils/share_links.dart';

/// Regression tests for the fifth-pass bug audit.
///
/// Each group is named after the user-visible symptom that used to be wrong,
/// so a change that reintroduces it fails here instead of in someone's hands.
void main() {
  group('Link host matching (R5-1, security)', () {
    // `h.endsWith('youtube.com')` also accepted `evil-youtube.com`, so a
    // hostile link could feed VibeTube a video id under a domain the user had
    // no reason to trust. Matching now requires a real label boundary.
    test('look-alike domains are rejected', () {
      for (final host in const [
        'evil-youtube.com',
        'myyoutube.com',
        'notyoutube.com',
        'youtube.com.attacker.net',
      ]) {
        expect(
          ShareLinks.parseVideoId(Uri.parse('https://$host/watch?v=dQw4w9WgXcQ')),
          isNull,
          reason: '$host must not be treated as YouTube',
        );
      }
    });

    test('the real domain and its subdomains still work', () {
      expect(
        ShareLinks.parseVideoId(Uri.parse('https://youtube.com/watch?v=dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
      expect(
        ShareLinks.parseVideoId(Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
      expect(
        ShareLinks.parseVideoId(Uri.parse('https://m.youtube.com/shorts/dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
      expect(
        ShareLinks.parseVideoId(Uri.parse('https://youtu.be/dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
    });
  });

  group('notifyListeners after dispose (R5-2)', () {
    // Every loader in AppProvider writes state and notifies *after* an await.
    // The request-id guards stop stale data from winning, but they do not help
    // once the provider itself is gone: ChangeNotifier throws
    // "used after being disposed" from a background future, which is an
    // unhandled async error rather than something a caller can catch.
    test('AppProvider tolerates a late notification', () {
      final provider = AppProvider();
      provider.dispose();
      expect(provider.notifyListeners, returnsNormally);
    });

    test('MiniPlayerController tolerates a late notification', () {
      final mini = MiniPlayerController();
      mini.dispose();
      expect(mini.notifyListeners, returnsNormally);
    });

    test('a live provider still notifies', () {
      final provider = AppProvider();
      addTearDown(provider.dispose);
      var calls = 0;
      provider.addListener(() => calls++);
      provider.notifyListeners();
      expect(calls, 1);
    });
  });

  group('Storage lock bookkeeping (R5-3)', () {
    // _synchronized kept one retained future per key forever, holding every
    // completed operation's closure — and the list of Videos it captured —
    // alive for the life of the process.
    test('the lock entry is released once the queue drains', () async {
      final storage = StorageService();
      expect(storage.debugPendingLockCount, 0);

      final first = storage.debugSynchronizedForTest('k', () async => 1);
      expect(storage.debugPendingLockCount, 1,
          reason: 'an in-flight operation must hold its lock');

      expect(await first, 1);
      await Future<void>.delayed(Duration.zero);
      expect(storage.debugPendingLockCount, 0,
          reason: 'the entry must be dropped once nothing is queued');
    });

    test('operations on one key still run in order', () async {
      final storage = StorageService();
      final order = <int>[];
      final a = storage.debugSynchronizedForTest('k', () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(1);
        return 1;
      });
      final b = storage.debugSynchronizedForTest('k', () async {
        order.add(2);
        return 2;
      });
      await Future.wait([a, b]);
      expect(order, [1, 2]);
    });

    test('a failure does not deadlock the queue or leak the lock', () async {
      final storage = StorageService();
      await expectLater(
        storage.debugSynchronizedForTest<int>('k', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await storage.debugSynchronizedForTest('k', () async => 7), 7);
      await Future<void>.delayed(Duration.zero);
      expect(storage.debugPendingLockCount, 0);
    });
  });
}
