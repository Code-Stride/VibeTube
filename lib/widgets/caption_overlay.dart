import 'package:flutter/material.dart';
import '../services/caption_service.dart';

/// Overlay widget that displays captions/subtitles over the video player.
class CaptionOverlay extends StatelessWidget {
  final List<CaptionCue> cues;
  final Duration position;
  final bool visible;

  const CaptionOverlay({
    super.key,
    required this.cues,
    required this.position,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || cues.isEmpty) return const SizedBox.shrink();

    final currentCue = _findCue(position);
    if (currentCue == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 60,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            currentCue.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.4,
              shadows: [
                Shadow(blurRadius: 4, color: Colors.black87),
                Shadow(blurRadius: 8, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Binary search over the (start-sorted) cue list.
  ///
  /// This runs on every player frame. A linear scan is fine for a 3-minute
  /// clip but a 2-hour talk has thousands of cues, and walking all of them
  /// 60x/second showed up as jank on low-end devices.
  CaptionCue? _findCue(Duration position) {
    final posMs = position.inMilliseconds;
    var lo = 0;
    var hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final cue = cues[mid];
      if (posMs < cue.start.inMilliseconds) {
        hi = mid - 1;
      } else if (posMs >= cue.end.inMilliseconds) {
        lo = mid + 1;
      } else {
        return cue;
      }
    }
    return null;
  }
}
