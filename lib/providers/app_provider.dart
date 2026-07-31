import 'package:flutter/material.dart';
import '../api/innertube_client.dart';
import '../models/video.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../services/native_player.dart';

class AppProvider extends ChangeNotifier {
  final InnerTubeClient _client = InnerTubeClient();
  final StorageService storage = StorageService();
  final UpdateService updates = UpdateService();
  final DownloadService downloader = DownloadService();

  List<Video> trendingVideos = [];
  List<Video> searchResults = [];
  List<Video> history = [];
  List<Video> liked = [];
  List<Video> watchLater = [];
  List<Video> downloads = [];
  List<Video> relatedVideos = [];
  List<Comment> comments = [];
  List<SponsorSegment> sponsorSegments = [];

  VideoDetails? currentVideo;
  int? dislikeCount;

  bool isLoading = false;
  bool isPlayerLoading = false;
  String? error;
  String? playerError;
  String searchQuery = '';
  String selectedCategory = 'All';

  // download progress videoId -> 0..1
  final Map<String, double> downloadProgress = {};
  final Set<String> downloadingIds = {};

  bool isDarkMode = true;
  bool isAdBlockEnabled = true;
  bool isSponsorBlockEnabled = true;
  bool isBackgroundPlayEnabled = true;
  bool isAutoPipEnabled = true;
  bool sbSponsor = true;
  bool sbSelfpromo = true;
  bool sbInteraction = true;
  bool sbIntro = false;
  bool sbOutro = false;
  bool sbFiller = false;
  String defaultQuality = 'Auto (HLS)';
  double defaultSpeed = 1.0;
  String region = 'IN';

  AppUpdateInfo? pendingUpdate;
  bool libraryLoaded = false;

  Future<void> init() async {
    final s = await storage.loadSettings();
    isDarkMode = s['isDarkMode'] ?? true;
    isAdBlockEnabled = s['isAdBlockEnabled'] ?? true;
    isSponsorBlockEnabled = s['isSponsorBlockEnabled'] ?? true;
    isBackgroundPlayEnabled = s['isBackgroundPlayEnabled'] ?? true;
    isAutoPipEnabled = s['isAutoPipEnabled'] ?? true;
    defaultQuality = s['defaultQuality'] ?? 'Auto (HLS)';
    defaultSpeed = (s['defaultSpeed'] as num?)?.toDouble() ?? 1.0;
    region = s['region'] ?? 'IN';
    sbSponsor = s['sbSponsor'] ?? true;
    sbSelfpromo = s['sbSelfpromo'] ?? true;
    sbInteraction = s['sbInteraction'] ?? true;
    sbIntro = s['sbIntro'] ?? false;
    sbOutro = s['sbOutro'] ?? false;
    sbFiller = s['sbFiller'] ?? false;
    await refreshLibrary();
    notifyListeners();
    loadTrending();
    checkUpdate();
  }

  Future<void> _persistSettings() async {
    await storage.saveSettings({
      'isDarkMode': isDarkMode,
      'isAdBlockEnabled': isAdBlockEnabled,
      'isSponsorBlockEnabled': isSponsorBlockEnabled,
      'isBackgroundPlayEnabled': isBackgroundPlayEnabled,
      'isAutoPipEnabled': isAutoPipEnabled,
      'defaultQuality': defaultQuality,
      'defaultSpeed': defaultSpeed,
      'region': region,
      'sbSponsor': sbSponsor,
      'sbSelfpromo': sbSelfpromo,
      'sbInteraction': sbInteraction,
      'sbIntro': sbIntro,
      'sbOutro': sbOutro,
      'sbFiller': sbFiller,
    });
  }

  Future<void> refreshLibrary() async {
    history = await storage.getHistory();
    liked = await storage.getLiked();
    watchLater = await storage.getWatchLater();
    downloads = await storage.getDownloads();
    libraryLoaded = true;
    notifyListeners();
  }

  Future<void> checkUpdate({bool force = false}) async {
    final info = await updates.checkForUpdate(force: force);
    if (info != null && info.hasUpdate) {
      pendingUpdate = info;
      notifyListeners();
    } else if (force) {
      pendingUpdate = info;
      notifyListeners();
    }
  }

  Future<void> dismissUpdate() async {
    if (pendingUpdate != null) {
      await updates.dismissVersion(pendingUpdate!.latestVersion);
      pendingUpdate = null;
      notifyListeners();
    }
  }

  Future<void> loadTrending() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      if (selectedCategory == 'All') {
        trendingVideos = await _client.getTrending(region: region);
      } else {
        trendingVideos =
            await _client.getCategoryFeed(selectedCategory, region: region);
      }
      if (trendingVideos.isEmpty) {
        error = 'No videos found. Check internet & pull to retry.';
      }
    } catch (e) {
      error = 'Failed to load feed. Pull to retry.\n$e';
      debugPrint('loadTrending: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setCategory(String cat) async {
    if (selectedCategory == cat) {
      await loadTrending();
      return;
    }
    selectedCategory = cat;
    trendingVideos = [];
    error = null;
    notifyListeners();
    await loadTrending();
  }

  Future<void> searchVideos(String query) async {
    searchQuery = query;
    if (query.trim().isEmpty) {
      searchResults = [];
      notifyListeners();
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _client.search(query);
      searchResults = result.videos;
      // Empty results are not a hard error — UI shows empty state
      error = null;
    } catch (e) {
      error = 'Search failed';
      searchResults = [];
      debugPrint('search: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    searchQuery = '';
    searchResults = [];
    notifyListeners();
  }

  Future<void> loadVideoDetails(String videoId, {Video? preview}) async {
    isPlayerLoading = true;
    playerError = null;
    // Keep previous related while loading new? clear for clarity
    currentVideo = null;
    relatedVideos = [];
    comments = [];
    sponsorSegments = [];
    dislikeCount = null;
    notifyListeners();

    try {
      final details = await _client.getVideoDetails(videoId);
      currentVideo = details;
      isPlayerLoading = false;
      notifyListeners();

      await storage.addToHistory(Video(
        id: details.id,
        title: details.title,
        thumbnailUrl: details.thumbnailUrl,
        channelName: details.channelName,
        channelId: details.channelId,
        viewCount: details.viewCount,
        duration: details.duration,
        publishedAt: details.publishedAt,
      ));
      history = await storage.getHistory();

      // side data — non-blocking for playback
      try {
        relatedVideos = await _client.getRelatedVideos(videoId);
        notifyListeners();
      } catch (e) {
        debugPrint('relatedVideos error: $e');
      }
      try {
        comments = await _client.getComments(videoId);
        notifyListeners();
      } catch (e) {
        debugPrint('comments error: $e');
      }
      try {
        if (isSponsorBlockEnabled) {
          sponsorSegments = await _client.getSponsorSegments(videoId);
        }
        notifyListeners();
      } catch (e) {
        debugPrint('sponsorSegments error: $e');
      }
      try {
        dislikeCount = await _client.getDislikeCount(videoId);
        notifyListeners();
      } catch (e) {
        debugPrint('dislikeCount error: $e');
      }
    } catch (e) {
      playerError = 'Could not load video stream.\n$e';
      isPlayerLoading = false;
      debugPrint('loadVideoDetails: $e');
      notifyListeners();
    }
  }

  /// Resolve a progressive URL for offline download.
  Future<String?> resolveDownloadUrl(String videoId) async {
    if (currentVideo?.id == videoId) {
      final muxed = currentVideo?.bestMuxedUrl;
      if (muxed != null && muxed.isNotEmpty) return muxed;
    }
    final d = await _client.getVideoDetails(videoId);
    return d.bestMuxedUrl ?? d.preferredPlayUrl;
  }

  Future<void> downloadVideo(Video video) async {
    if (downloadingIds.contains(video.id)) return;
    downloadingIds.add(video.id);
    downloadProgress[video.id] = 0;
    notifyListeners();
    try {
      final url = await resolveDownloadUrl(video.id);
      if (url == null || url.isEmpty) {
        throw Exception('No downloadable stream for this video');
      }
      final path = await downloader.downloadVideo(
        video: video,
        streamUrl: url,
        onProgress: (p) {
          downloadProgress[video.id] = p;
          notifyListeners();
        },
      );
      final saved = video.copyWith(localPath: path);
      await storage.addDownload(saved);
      downloads = await storage.getDownloads();
    } finally {
      downloadingIds.remove(video.id);
      downloadProgress.remove(video.id);
      notifyListeners();
    }
  }

  Future<void> removeDownload(String id) async {
    await downloader.delete(id);
    await storage.removeDownload(id);
    downloads = await storage.getDownloads();
    notifyListeners();
  }

  Future<bool> toggleLike(Video video) async {
    final likedNow = await storage.toggleLiked(video);
    liked = await storage.getLiked();
    notifyListeners();
    return likedNow;
  }

  Future<bool> isLiked(String id) => storage.isLiked(id);

  Future<bool> toggleWatchLater(Video video) async {
    final now = await storage.toggleWatchLater(video);
    watchLater = await storage.getWatchLater();
    notifyListeners();
    return now;
  }

  /// Legacy list-only add (meta). Prefer [downloadVideo].
  Future<void> addDownload(Video video) => downloadVideo(video);

  Future<void> clearHistory() async {
    await storage.clearHistory();
    history = [];
    notifyListeners();
  }

  void toggleDarkMode() {
    isDarkMode = !isDarkMode;
    _persistSettings();
    notifyListeners();
  }

  void toggleAdBlock() {
    isAdBlockEnabled = !isAdBlockEnabled;
    _persistSettings();
    notifyListeners();
  }

  void toggleSponsorBlock() {
    isSponsorBlockEnabled = !isSponsorBlockEnabled;
    _persistSettings();
    notifyListeners();
  }

  void toggleBackgroundPlay() {
    isBackgroundPlayEnabled = !isBackgroundPlayEnabled;
    if (!isBackgroundPlayEnabled) {
      NativePlayer.stopBackground();
    }
    _persistSettings();
    notifyListeners();
  }

  void toggleAutoPip() {
    isAutoPipEnabled = !isAutoPipEnabled;
    NativePlayer.setAutoPip(isAutoPipEnabled);
    _persistSettings();
    notifyListeners();
  }

  void setSbCategory(String key, bool val) {
    switch (key) {
      case 'sponsor':
        sbSponsor = val;
        break;
      case 'selfpromo':
        sbSelfpromo = val;
        break;
      case 'interaction':
        sbInteraction = val;
        break;
      case 'intro':
        sbIntro = val;
        break;
      case 'outro':
        sbOutro = val;
        break;
      case 'filler':
        sbFiller = val;
        break;
    }
    _persistSettings();
    notifyListeners();
  }

  bool sbEnabled(String category) {
    switch (category) {
      case 'sponsor':
        return sbSponsor;
      case 'selfpromo':
        return sbSelfpromo;
      case 'interaction':
        return sbInteraction;
      case 'intro':
        return sbIntro;
      case 'outro':
        return sbOutro;
      case 'filler':
        return sbFiller;
      default:
        return true;
    }
  }

  void setDefaultQuality(String q) {
    defaultQuality = q;
    _persistSettings();
    notifyListeners();
  }

  void setDefaultSpeed(double s) {
    defaultSpeed = s;
    _persistSettings();
    notifyListeners();
  }

  List<SponsorSegment> get activeSponsorSegments {
    if (!isSponsorBlockEnabled) return [];
    return sponsorSegments.where((s) => sbEnabled(s.category)).toList();
  }

  @override
  void dispose() {
    _client.dispose();
    downloader.dispose();
    super.dispose();
  }
}
