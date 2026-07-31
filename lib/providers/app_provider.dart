import 'package:flutter/material.dart';
import '../api/innertube_client.dart';
import '../models/video.dart';
import '../services/download_service.dart';
import '../services/hls_parser.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../services/native_player.dart';
import '../services/caption_service.dart';

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
  List<Video> shortsVideos = [];
  List<Comment> comments = [];
  List<SponsorSegment> sponsorSegments = [];

  VideoDetails? currentVideo;
  int? dislikeCount;

  bool isLoading = false;
  bool isPlayerLoading = false;
  bool isShortsLoading = false;
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

  // Captions
  bool isCaptionsEnabled = false;
  List<CaptionTrack> captionTracks = [];
  List<CaptionCue> captionCues = [];
  String? selectedCaptionLanguage;

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
    isCaptionsEnabled = s['isCaptionsEnabled'] ?? false;
    selectedCaptionLanguage = s['selectedCaptionLanguage'];
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
      'isCaptionsEnabled': isCaptionsEnabled,
      'selectedCaptionLanguage': selectedCaptionLanguage,
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

  // ---- Shorts ----

  Future<void> loadShorts() async {
    isShortsLoading = true;
    notifyListeners();
    try {
      shortsVideos = await _client.getCategoryFeed('Shorts', region: region);
      if (shortsVideos.isEmpty) {
        // Fallback: search for shorts
        final result = await _client.search('#shorts', params: InnerTubeClient.kFilterShorts);
        shortsVideos = result.videos;
      }
    } catch (e) {
      debugPrint('loadShorts: $e');
    } finally {
      isShortsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreShorts() async {
    try {
      final more = await _client.search('shorts', params: InnerTubeClient.kFilterShorts);
      final seen = shortsVideos.map((v) => v.id).toSet();
      for (final v in more.videos) {
        if (seen.add(v.id)) {
          shortsVideos.add(v);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadMoreShorts: $e');
    }
  }

  // ---- Captions ----

  Future<void> loadCaptions(String videoId) async {
    try {
      captionTracks = await CaptionService.getTracks(videoId);
      if (captionTracks.isNotEmpty && isCaptionsEnabled) {
        // Auto-select preferred language or first available
        final preferred = selectedCaptionLanguage;
        final track = captionTracks.firstWhere(
          (t) => t.languageCode == preferred,
          orElse: () => captionTracks.first,
        );
        await selectCaptionTrack(track);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadCaptions: $e');
    }
  }

  Future<void> selectCaptionTrack(CaptionTrack track) async {
    try {
      captionCues = await CaptionService.getCues(track.baseUrl);
      selectedCaptionLanguage = track.languageCode;
      notifyListeners();
    } catch (e) {
      debugPrint('selectCaptionTrack: $e');
    }
  }

  void toggleCaptions() {
    isCaptionsEnabled = !isCaptionsEnabled;
    if (!isCaptionsEnabled) {
      captionCues = [];
    }
    _persistSettings();
    notifyListeners();
  }

  void clearCaptions() {
    captionTracks = [];
    captionCues = [];
    notifyListeners();
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
      // Load captions
      try {
        await loadCaptions(videoId);
      } catch (e) {
        debugPrint('captions error: $e');
      }
    } catch (e) {
      playerError = 'Could not load video stream.\n$e';
      isPlayerLoading = false;
      debugPrint('loadVideoDetails: $e');
      notifyListeners();
    }
  }

  /// Resolve a progressive URL for offline download.
  ///
  /// Only progressive (muxed MP4) streams are usable offline. An HLS/DASH
  /// manifest is a text playlist — saving it as `.mp4` produces a file that
  /// looks downloaded but never plays, so we reject it explicitly.
  Future<String?> resolveDownloadUrl(String videoId) async {
    bool isProgressive(String? u) =>
        u != null &&
        u.isNotEmpty &&
        !u.contains('.m3u8') &&
        !u.contains('/manifest/hls') &&
        !u.contains('/manifest/dash');

    if (currentVideo?.id == videoId) {
      final muxed = currentVideo?.bestMuxedUrl;
      if (isProgressive(muxed)) return muxed;
    }
    final d = await _client.getVideoDetails(videoId);
    if (d.isLive) {
      throw Exception('Live streams cannot be downloaded');
    }
    final muxed = d.bestMuxedUrl;
    if (isProgressive(muxed)) return muxed;
    final fallback = d.preferredPlayUrl;
    if (isProgressive(fallback)) return fallback;
    throw Exception('No downloadable (progressive) stream for this video');
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
      // Throttle UI updates: the HTTP stream fires per chunk, which would
      // rebuild the widget tree hundreds of times per second.
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      var lastPct = -1;
      final path = await downloader.downloadVideo(
        video: video,
        streamUrl: url,
        onProgress: (p) {
          downloadProgress[video.id] = p;
          final now = DateTime.now();
          final pct = (p * 100).floor();
          final done = p >= 1.0;
          if (done ||
              (pct != lastPct &&
                  now.difference(lastNotify).inMilliseconds >= 200)) {
            lastNotify = now;
            lastPct = pct;
            notifyListeners();
          }
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

  void setRegion(String r) {
    region = r;
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
    HlsParser.dispose();
    super.dispose();
  }
}
