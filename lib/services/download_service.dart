import 'dart:async';
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
    final path = await pathFor(videoId);
    return _isValidMp4(File(path));
  }

  Future<bool> _isValidMp4(File file) async {
    if (!await file.exists() || await file.length() < 12) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(12);
      return hasIsoBmffHeader(header);
    } finally {
      await handle.close();
    }
  }

  /// ISO-BMFF files have an `ftyp` box at byte 4. Keeping this pure makes the
  /// integrity rule directly unit-testable without platform storage plugins.
  static bool hasIsoBmffHeader(List<int> header) =>
      header.length >= 12 &&
      header[4] == 0x66 &&
      header[5] == 0x74 &&
      header[6] == 0x79 &&
      header[7] == 0x70;

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
      if (await _isValidMp4(file)) {
        onProgress?.call(1);
        return path;
      }
      // Suspiciously small — likely a partial/corrupt file; delete and retry
      try {
        await file.delete();
      } catch (_) {}
    }

    // Clean up any leftover .part file from a previous failed attempt
    final partFile = File('$path.part');
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
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
      try {
        await partFile.delete();
      } catch (_) {}
      rethrow;
    }

    if (res.statusCode != 200) {
      throw Exception('Download failed HTTP ${res.statusCode}');
    }
    final contentType = res.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/html') ||
        contentType.contains('application/json')) {
      throw Exception('Download returned $contentType instead of video');
    }
    final total = res.contentLength ?? 0;
    final sink = partFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 45),
        onTimeout: (sink) =>
            sink.addError(TimeoutException('Download stalled for 45 seconds')),
      )) {
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
      try {
        await partFile.delete();
      } catch (_) {}
      rethrow;
    }

    // A dropped connection ends the stream without an error, so "we got some
    // bytes and they start with ftyp" was enough to rename a half-finished
    // file to .mp4 and list it as a complete download. Compare against the
    // advertised length before trusting it.
    if (total > 0 && received < total) {
      try {
        await partFile.delete();
      } catch (_) {}
      throw Exception(
        'Download incomplete: got $received of $total bytes',
      );
    }

    if (!await _isValidMp4(partFile)) {
      try {
        await partFile.delete();
      } catch (_) {}
      throw Exception('Downloaded response is not a valid MP4');
    }

    // Rename .part → .mp4 only on complete success
    await partFile.rename(path);
    onProgress?.call(1);
    return path;
  }

  Future<void> delete(String videoId) async {
    final p = await pathFor(videoId);
    final f = File(p);
    // best-effort: a missing file (already gone / never finished) or a
    // file held open by another handle used to throw here, which aborted
    // removeDownload() before it could clean up the metadata row — leaving
    // a Downloads entry that pointed at nothing.
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void dispose() => _http.close();
}
