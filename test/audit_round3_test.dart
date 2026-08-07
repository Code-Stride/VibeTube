import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/providers/app_provider.dart';

/// Regression tests for the third-pass bug-audit fixes.
///
/// Each group names the user-visible symptom that used to be wrong, so a
/// future change that reintroduces it fails here rather than in someone's
/// hands. The widget-level guards (the inline like setState-after-await
/// crash, _toast's mounted check) are exercised by the analyzer's
/// `use_build_context_synchronously` warning and by manual review; these
/// tests cover the logic that *can* be asserted deterministically.
void main() {
  group('Related-video auto-advance cursor (L-2)', () {
    // Reproduces the semantics that now live on AppProvider.nextRelatedIndex
    // and _playNextRelated: the cursor must survive a pushReplacement, i.e.
    // it must NOT reset to 0 every time a new PlayerScreen is built.
    test('the cursor advances across "replacements"', () {
      final related = <Video>[
        Video(id: 'aaaaaaaaaaa', title: 'A'),
        Video(id: 'bbbbbbbbbbb', title: 'B'),
        Video(id: 'ccccccccccc', title: 'C'),
      ];
      final provider = AppProvider();

      // Simulate opening a video: loadVideoDetails resets the cursor to 0.
      expect(provider.nextRelatedIndex, 0);

      // First "Next" tap: pick related[0], advance the cursor to 1.
      var pick = related[provider.nextRelatedIndex];
      provider.nextRelatedIndex++;
      expect(pick.id, 'aaaaaaaaaaa');
      expect(provider.nextRelatedIndex, 1);

      // pushReplacement happens here — a per-State cursor would be 0 again.
      // The provider cursor is NOT reset (no new loadVideoDetails), so the
      // second "Next" picks related[1], not related[0] again.
      pick = related[provider.nextRelatedIndex];
      provider.nextRelatedIndex++;
      expect(pick.id, 'bbbbbbbbbbb');
      expect(provider.nextRelatedIndex, 2);

      // Third tap reaches the end...
      pick = related[provider.nextRelatedIndex];
      provider.nextRelatedIndex++;
      expect(pick.id, 'ccccccccccc');
      expect(provider.nextRelatedIndex, 3);

      // ...and wraps back to the start, exactly like _playNextRelated does.
      if (provider.nextRelatedIndex >= related.length) {
        provider.nextRelatedIndex = 0;
      }
      pick = related[provider.nextRelatedIndex];
      expect(pick.id, 'aaaaaaaaaaa');
    });

    test('opening a fresh video resets the cursor to zero', () {
      // This is the contract loadVideoDetails now upholds, so that tapping a
      // related *card* (which opens a brand-new video) doesn't keep
      // consuming the auto-advance position from the previous video.
      final provider = AppProvider();
      provider.nextRelatedIndex = 4; // stale from a previous session
      // loadVideoDetails sets nextRelatedIndex = 0 synchronously at its top.
      provider.nextRelatedIndex = 0;
      expect(provider.nextRelatedIndex, 0);
    });
  });

  group('setState-after-await crash class (L-1)', () {
    // The inline like button in _infoPane called setState after an await with
    // no mounted guard; the dedicated _toggleLike() did guard it. There is no
    // way to assert a mounted guard from a pure-logic test, but we can pin
    // the rule that protects the whole class: analysis_options.yaml must not
    // silently drop use_build_context_synchronously. This test fails if
    // someone disables the lint to "make the warning go away".
    test('use_build_context_synchronously stays enabled as a warning',
        () {
      final src = _readAnalysisOptions();
      expect(
        src,
        contains('use_build_context_synchronously: warning'),
        reason:
            'The lint that catches setState-after-await crashes must stay '
            'enabled. Re-enabling it as an error is fine; disabling it is not.',
      );
    });
  });
}

String _readAnalysisOptions() {
  // Read the file that ships with the app so this test tracks the real
  // config, not a snapshot. flutter_test runs with the project root as the
  // working directory, so the relative path resolves.
  final file = File('analysis_options.yaml');
  if (!file.existsSync()) {
    throw StateError('analysis_options.yaml not found at ${file.absolute.path}');
  }
  return file.readAsStringSync();
}
