import 'package:flutter/material.dart';
import '../api/innertube_client.dart';
import '../models/video.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';

class AppProvider extends ChangeNotifier {
  final InnerTubeClient _client = InnerTubeClient();
  final StorageService storage = StorageService();
  final UpdateService updates = UpdateService();

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

  // Settings
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
  String defaultQuality = 'Auto';
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
    defaultQuality = s['defaultQuality'] ?? 'Auto';
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
    // fire and forget
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
        if (trendingVideos.isEmpty) {
          trendingVideos = await _client.getHomeFeed(region: region);
        }
      } else {
        final r = await _client.search(selectedCategory);
        trendingVideos = r.videos;
      }
      if (trendingVideos.isEmpty) {
        error = 'No videos found. Check your internet connection.';
      }
    } catch (e) {
      error = 'Failed to load feed. Pull to retry.';
      debugPrint('loadTrending: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setCategory(String cat) async {
    selectedCategory = cat;
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
    } catch (e) {
      error = 'Search failed';
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

  /// Instant-play path: load details + streams + side data.
  Future<void> loadVideoDetails(String videoId, {Video? preview}) async {
    isPlayerLoading = true;
    playerError = null;
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

      // history
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

      // parallel side loads (non-blocking for playback)
      final relatedF = _client.getRelatedVideos(videoId);
      final commentsF = _client.getComments(videoId);
      final sbF = isSponsorBlockEnabled
          ? _client.getSponsorSegments(videoId)
          : Future.value(<SponsorSegment>[]);
      final dislikeF = _client.getDislikeCount(videoId);

      relatedVideos = await relatedF;
      notifyListeners();
      comments = await commentsF;
      sponsorSegments = await sbF;
      dislikeCount = await dislikeF;
      notifyListeners();
    } catch (e) {
      playerError = 'Could not play this video.\n$e';
      isPlayerLoading = false;
      debugPrint('loadVideoDetails: $e');
      notifyListeners();
    }
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

  Future<void> addDownload(Video video) async {
    await storage.addDownload(video);
    downloads = await storage.getDownloads();
    notifyListeners();
  }

  Future<void> removeDownload(String id) async {
    await storage.removeDownload(id);
    downloads = await storage.getDownloads();
    notifyListeners();
  }

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
    _persistSettings();
    notifyListeners();
  }

  void toggleAutoPip() {
    isAutoPipEnabled = !isAutoPipEnabled;
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
    super.dispose();
  }
}
