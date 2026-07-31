import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/video.dart';

class DownloadService {
  final http.Client _http = http.Client();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> pathFor(String videoId) async {
    final d = await _dir();
    return '${d.path}/$videoId.mp4';
  }

  Future<bool> isDownloaded(String videoId) async {
    final p = await pathFor(videoId);
    return File(p).exists();
  }

  /// Download progressive MP4 URL to app storage.
  /// Uses a .part file during download, renamed on completion to avoid
  /// serving partial/corrupted files as complete downloads.
  Future<String> downloadVideo({
    required Video video,
    required String streamUrl,
    void Function(double progress)? onProgress,
  }) async {
    final path = await pathFor(video.id);
    final file = File(path);

    // Check for a fully completed file (exists with .mp4 extension, not .part)
    if (await file.exists()) {
      final len = await file.length();
      // A valid MP4 is at least 50KB (tiny videos are still >100KB)
      if (len > 50000) {
        onProgress?.call(1);
        return path;
      }
      // Suspiciously small — likely a partial/corrupt file; delete and retry
      try { await file.delete(); } catch (_) {}
    }

    // Clean up any leftover .part file from a previous failed attempt
    final partFile = File('$path.part');
    if (await partFile.exists()) {
      try { await partFile.delete(); } catch (_) {}
    }

    final req = http.Request('GET', Uri.parse(streamUrl));
    req.headers.addAll({
      'User-Agent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      'Referer': 'https://www.youtube.com/',
      'Accept': '*/*',
    });

    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(const Duration(minutes: 30));
    } catch (e) {
      // Clean up partial file on network error
      try { await partFile.delete(); } catch (_) {}
      rethrow;
    }

    if (res.statusCode != 200) {
      throw Exception('Download failed HTTP ${res.statusCode}');
    }
    final total = res.contentLength ?? 0;
    final sink = partFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        } else {
          // Server sent no Content-Length: we cannot compute a real ratio.
          // Report a slowly saturating estimate so the UI still moves.
          onProgress?.call(1 - (1 / (1 + received / 8000000)));
        }
      }
      await sink.close();
    } catch (e) {
      // Clean up partial file on stream error
      await sink.close();
      try { await partFile.delete(); } catch (_) {}
      rethrow;
    }

    // Rename .part → .mp4 only on complete success
    await partFile.rename(path);
    onProgress?.call(1);
    return path;
  }

  Future<void> delete(String videoId) async {
    final p = await pathFor(videoId);
    final f = File(p);
    if (await f.exists()) await f.delete();
  }

  void dispose() => _http.close();
}
