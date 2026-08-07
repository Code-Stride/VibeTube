import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural regression checks for lifecycle/security fixes that require
/// native video decoders, Android broadcasts, or GitHub Actions to reproduce.
/// Runtime behavior is additionally covered by CI analyzer/build and the
/// manual rapid-swipe test plan in docs/BUG_SCAN_REPORT.md.
void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Short players have stable video identity and stale-play guards', () {
    final dart = source('lib/screens/shorts_screen.dart');
    expect(dart, contains('key: ValueKey(video.id)'));
    expect(dart, contains('expectedRequest != _playerRequestId'));
    expect(dart, contains('!widget.isActive'));
    expect(dart, contains('if (!identical(_controller, controller))'));
  });

  test('next-response cache does not create an ignored catchError future', () {
    final dart = source('lib/api/innertube_client.dart');
    final start = dart.indexOf('Future<Map<String, dynamic>> _fetchNext');
    final end = dart.indexOf('Future<List<Video>> getRelatedVideos', start);
    final method = dart.substring(start, end);
    expect(method, isNot(contains('.catchError')));
    expect(method, contains('return await future'));
    expect(method, contains('identical(_nextCacheFuture, future)'));
  });

  test('release workflow pins actions and verifies signing certificate', () {
    final yaml = source('.github/workflows/build.yml');
    expect(yaml, isNot(contains('uses: actions/checkout@v')));
    expect(yaml, isNot(contains('uses: actions/setup-java@v')));
    expect(yaml, isNot(contains('uses: subosito/flutter-action@v')));
    expect(yaml, contains('VIBETUBE_EXPECTED_CERT_SHA256'));
    expect(yaml, contains('Release signing certificate fingerprint mismatch'));
  });

  test('pre-Android 13 PiP commands require an unguessable capability', () {
    final kotlin = source(
      'android/app/src/main/kotlin/com/blazenxt/vibetube/MainActivity.kt',
    );
    expect(kotlin, contains('UUID.randomUUID().toString()'));
    expect(kotlin, contains('EXTRA_PIP_NONCE'));
    expect(kotlin, contains('!= pipNonce) return'));
  });
}
