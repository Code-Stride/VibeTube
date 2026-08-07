import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video.dart';

/// Outcome of an update check.
///
/// Previously both "you are on the latest version" and "the network call
/// failed" returned null, so Settings cheerfully reported *"You are on the
/// latest version"* while offline.
enum UpdateStatus { upToDate, updateAvailable, failed }

class UpdateCheckResult {
  final UpdateStatus status;
  final AppUpdateInfo? info;
  const UpdateCheckResult(this.status, [this.info]);

  bool get hasUpdate => status == UpdateStatus.updateAvailable && info != null;
}

/// Checks GitHub Releases for newer APK versions and shows update popup.
class UpdateService {
  static const String repoOwner = 'Code-Stride';
  static const String repoName = 'VibeTube';
  static const String prefsKeyDismissed = 'update_dismissed_version';

  /// Backwards-compatible wrapper returning only an actionable update.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async =>
      (await check(force: force)).info;

  Future<UpdateCheckResult> check({bool force = false}) async {
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

      if (res.statusCode != 200) {
        return const UpdateCheckResult(UpdateStatus.failed);
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Only strip a leading "v" (e.g. "v1.5.0"), not a "v" anywhere in the tag.
      final tag = (data['tag_name'] as String? ?? '')
          .trim()
          .replaceFirst(RegExp(r'^[vV]'), '');
      if (tag.isEmpty) return const UpdateCheckResult(UpdateStatus.failed);

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(prefsKeyDismissed);
      if (!force && dismissed == tag) {
        return const UpdateCheckResult(UpdateStatus.upToDate);
      }

      final hasUpdate = _isNewer(tag, current, localBuild: build);
      // NEVER show update popup when app is already on latest version
      if (!hasUpdate) return const UpdateCheckResult(UpdateStatus.upToDate);

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

      return UpdateCheckResult(
        UpdateStatus.updateAvailable,
        AppUpdateInfo(
          latestVersion: tag,
          currentVersion: '$current+$build',
          releaseNotes: data['body']?.toString() ?? 'Bug fixes and improvements',
          downloadUrl: apkUrl,
          hasUpdate: hasUpdate,
        ),
      );
    } catch (_) {
      return const UpdateCheckResult(UpdateStatus.failed);
    }
  }

  Future<void> dismissVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyDismissed, version);
  }

  /// Semver-ish compare: returns true if remote > local.
  ///
  /// When the three version components tie, the build number breaks the tie —
  /// otherwise re-releasing `1.11.0+27` over `1.11.0+26` never prompted.
  bool _isNewer(String remote, String local, {String? localBuild}) {
    List<int> parse(String v) {
      // Strip any build metadata ("1.5.0+11") and pre-release suffix first,
      // then keep only digits and dots.
      final core = v.split('+').first.split('-').first;
      final cleaned = core.replaceAll(RegExp(r'[^0-9.]'), '');
      final parts = cleaned.split('.');
      return [
        int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
        int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
        int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
      ];
    }

    final r = parse(remote);
    final l = parse(local);
    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    // Same x.y.z — compare build metadata ("1.11.0+27" vs local build 26).
    final remoteBuild = int.tryParse(
        remote.contains('+') ? remote.split('+').last.split('-').first : '');
    final currentBuild = int.tryParse(localBuild ?? '');
    if (remoteBuild != null && currentBuild != null) {
      return remoteBuild > currentBuild;
    }
    return false;
  }
}
