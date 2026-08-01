import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video.dart';

class StorageService {
  static const _kHistory = 'watch_history';
  static const _kLiked = 'liked_videos';
  static const _kWatchLater = 'watch_later';
  static const _kDownloads = 'downloads_meta';
  static const _kSettings = 'app_settings';
  static const _kSearchHistory = 'search_history';

  SharedPreferences? _prefs;
  Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<Map<String, dynamic>> loadSettings() async {
    final p = await prefs;
    final raw = p.getString(_kSettings);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> s) async {
    final p = await prefs;
    await p.setString(_kSettings, jsonEncode(s));
  }

  Future<List<Video>> getList(String key) async {
    final p = await prefs;
    final raw = p.getStringList(key) ?? [];
    return raw
        .map((e) {
          try {
            return Video.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Video>()
        .toList();
  }

  Future<void> setList(String key, List<Video> videos) async {
    final p = await prefs;
    await p.setStringList(
      key,
      videos.map((v) => jsonEncode(v.toJson())).toList(),
    );
  }

  Future<List<Video>> getHistory() => getList(_kHistory);
  Future<List<Video>> getLiked() => getList(_kLiked);
  Future<List<Video>> getWatchLater() => getList(_kWatchLater);
  Future<List<Video>> getDownloads() => getList(_kDownloads);

  Future<void> addToHistory(Video video) async {
    final list = await getHistory();
    list.removeWhere((v) => v.id == video.id);
    list.insert(0, video);
    if (list.length > 100) list.removeRange(100, list.length);
    await setList(_kHistory, list);
  }

  Future<bool> toggleLiked(Video video) async {
    final list = await getLiked();
    final exists = list.any((v) => v.id == video.id);
    if (exists) {
      list.removeWhere((v) => v.id == video.id);
      await setList(_kLiked, list);
      return false;
    } else {
      list.insert(0, video);
      await setList(_kLiked, list);
      return true;
    }
  }

  Future<bool> isLiked(String id) async {
    final list = await getLiked();
    return list.any((v) => v.id == id);
  }

  Future<bool> toggleWatchLater(Video video) async {
    final list = await getWatchLater();
    final exists = list.any((v) => v.id == video.id);
    if (exists) {
      list.removeWhere((v) => v.id == video.id);
      await setList(_kWatchLater, list);
      return false;
    } else {
      list.insert(0, video);
      await setList(_kWatchLater, list);
      return true;
    }
  }

  Future<void> addDownload(Video video) async {
    final list = await getDownloads();
    list.removeWhere((v) => v.id == video.id);
    list.insert(0, video);
    await setList(_kDownloads, list);
  }

  Future<void> removeDownload(String id) async {
    final list = await getDownloads();
    list.removeWhere((v) => v.id == id);
    await setList(_kDownloads, list);
  }

  Future<void> clearHistory() async => setList(_kHistory, []);

  // ---- Search History ----

  Future<List<String>> getSearchHistory() async {
    final p = await prefs;
    return p.getStringList(_kSearchHistory) ?? [];
  }

  Future<void> addSearchQuery(String query) async {
    final p = await prefs;
    final list = p.getStringList(_kSearchHistory) ?? [];
    list.remove(query);
    list.insert(0, query);
    if (list.length > 30) list.removeRange(30, list.length);
    await p.setStringList(_kSearchHistory, list);
  }

  Future<void> removeSearchQuery(String query) async {
    final p = await prefs;
    final list = p.getStringList(_kSearchHistory) ?? [];
    list.remove(query);
    await p.setStringList(_kSearchHistory, list);
  }

  Future<void> clearSearchHistory() async {
    final p = await prefs;
    await p.remove(_kSearchHistory);
  }
}
