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
  Future<String> downloadVideo({
    required Video video,
    required String streamUrl,
    void Function(double progress)? onProgress,
  }) async {
    final path = await pathFor(video.id);
    final file = File(path);
    if (await file.exists() && await file.length() > 1000) {
      onProgress?.call(1);
      return path;
    }

    final req = http.Request('GET', Uri.parse(streamUrl));
    req.headers.addAll({
      'User-Agent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      'Referer': 'https://www.youtube.com/',
      'Accept': '*/*',
    });
    final res = await _http.send(req).timeout(const Duration(minutes: 30));
    if (res.statusCode != 200) {
      throw Exception('Download failed HTTP ${res.statusCode}');
    }
    final total = res.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
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
