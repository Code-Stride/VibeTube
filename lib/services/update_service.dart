import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video.dart';

/// Checks GitHub Releases for newer APK versions and shows update popup.
class UpdateService {
  static const String repoOwner = 'Code-Stride';
  static const String repoName = 'VibeTube';
  static const String prefsKeyDismissed = 'update_dismissed_version';

  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. 1.1.0
      final build = info.buildNumber;

      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final res = await http.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'VibeTube/$current',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Only strip a leading "v" (e.g. "v1.5.0"), not a "v" anywhere in the tag.
      final tag = (data['tag_name'] as String? ?? '')
          .trim()
          .replaceFirst(RegExp(r'^[vV]'), '');
      if (tag.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(prefsKeyDismissed);
      if (!force && dismissed == tag) return null;

      // Compare against version+build so a same-version hotfix (1.11.0+27
      // over 1.11.0+26) is still detected.
      final hasUpdate = isNewer(tag, '$current+$build');
      // NEVER show update popup when app is already on latest version
      if (!hasUpdate) return null;

      String apkUrl = data['html_url']?.toString() ??
          'https://github.com/$repoOwner/$repoName/releases/latest';
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final a in assets) {
        final name = a['name']?.toString().toLowerCase() ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url']?.toString() ?? apkUrl;
          break;
        }
      }

      return AppUpdateInfo(
        latestVersion: tag,
        currentVersion: '$current+$build',
        releaseNotes: data['body']?.toString() ?? 'Bug fixes and improvements',
        downloadUrl: apkUrl,
        hasUpdate: hasUpdate,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> dismissVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyDismissed, version);
  }

  /// `[major, minor, patch, build]`.
  ///
  /// The build component comes from the `+N` suffix and is `0` when absent,
  /// which is what a plain release tag like `v1.11.0` yields — so an untagged
  /// build never looks newer than an installed one with the same core.
  @visibleForTesting
  static List<int> parseVersion(String v) {
    final plus = v.indexOf('+');
    final buildPart = plus >= 0 ? v.substring(plus + 1) : '';
    // Strip build metadata and any pre-release suffix, then keep digits/dots.
    final core = v.split('+').first.split('-').first;
    final cleaned = core.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = cleaned.split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
      int.tryParse(buildPart.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    ];
  }

  /// Semver-ish compare: returns true if remote > local.
  @visibleForTesting
  static bool isNewer(String remote, String local) {
    final r = parseVersion(remote);
    final l = parseVersion(local);
    for (var i = 0; i < 4; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }
}
