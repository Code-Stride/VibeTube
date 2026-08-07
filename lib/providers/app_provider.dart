import 'dart:async';
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
  InnerTubeClient get client => _client;
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
  List<Video> musicVideos = []; // YouTube Music section
  List<Comment> comments = [];
  List<SponsorSegment> sponsorSegments = [];

  List<String> searchHistory = [];

  VideoDetails? currentVideo;
  int? dislikeCount;

  // Feed and search used to share one `isLoading`/`error` pair. Because
  // SearchScreen lives permanently inside HomeScreen's IndexedStack, a home
  // refresh spun the search tab and a failed search painted an error over the
  // home feed. They are independent now.
  bool isFeedLoading = false;
  bool isSearchLoading = false;
  bool isPlayerLoading = false;
  bool isShortsLoading = false;
  String? feedError;
  String? searchError;
  String? playerError;
  String searchQuery = '';
  String selectedCategory = 'All';

  // Pagination tokens
  String? _searchContinuation;
  String? _shortsContinuation;
  bool isLoadingMoreSearch = false;
  bool isLoadingMoreShorts = false;
  bool get hasMoreSearch =>
      _searchContinuation != null && _searchContinuation!.isNotEmpty;

  // Monotonic request IDs prevent stale async responses from overwriting
  // newer user intent (fast searches, category changes, and A→B navigation).
  int _feedRequestId = 0;
  int _searchRequestId = 0;
  int _videoRequestId = 0;
  int _loadingRequestId = 0;
  int _shortsRequestId = 0;
  int _musicRequestId = 0;

  // download progress videoId -> 0..1
  final Map<String, double> downloadProgress = {};
  final Set<String> downloadingIds = {};
  /// videoId -> title, so the Downloads tab can name in-flight items.
  final Map<String, String> downloadTitles = {};

  bool isDarkMode = true;
  bool isMusicMode = false;
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
  /// True when the last update check could not reach GitHub, so the UI can say
  /// "check failed" instead of "you are up to date".
  bool lastUpdateCheckFailed = false;
  bool libraryLoaded = false;

  /// False when POST_NOTIFICATIONS was denied: the media notification (and
  /// therefore background playback controls) cannot appear.
  bool notificationsAllowed = true;

  void setNotificationsAllowed(bool v) {
    if (notificationsAllowed == v) return;
    notificationsAllowed = v;
    notifyListeners();
  }

  /// Channel ids the user subscribed to (persisted).
  Set<String> subscriptions = <String>{};
  bool isSubscribed(String? channelId) =>
      channelId != null && channelId.isNotEmpty &&
      subscriptions.contains(channelId);

  Future<void> init() async {
    final s = await storage.loadSettings();
    isDarkMode = s['isDarkMode'] ?? true;
    isMusicMode = s['isMusicMode'] ?? false;
    isAdBlockEnabled = s['isAdBlockEnabled'] ?? true;
    isSponsorBlockEnabled = s['isSponsorBlockEnabled'] ?? true;
    isBackgroundPlayEnabled = s['isBackgroundPlayEnabled'] ?? true;
    isAutoPipEnabled = s['isAutoPipEnabled'] ?? true;
    // Default to adaptive streaming, matching the field declaration. The old
    // '1080p' fallback hard-locked every fresh install to a height many
    // videos do not have, producing "1080p is not available" on first play.
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
    searchHistory = await storage.getSearchHistory();
    subscriptions = await storage.getSubscriptions();
    notifyListeners();
    loadTrending();
    checkUpdate();
  }

  Future<void> _persistSettings() async {
    await storage.saveSettings({
      'isDarkMode': isDarkMode,
      'isMusicMode': isMusicMode,
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
    final result = await updates.check(force: force);
    lastUpdateCheckFailed = result.status == UpdateStatus.failed;
    if (result.hasUpdate) {
      pendingUpdate = result.info;
      notifyListeners();
    } else if (force) {
      pendingUpdate = null;
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
    final requestId = ++_feedRequestId;
    final category = selectedCategory;
    final requestRegion = region;
    final loadingId = ++_loadingRequestId;
    isFeedLoading = true;
    feedError = null;
    notifyListeners();
    try {
      final videos = category == 'All'
          ? await _client.getTrending(region: requestRegion)
          : await _client.getCategoryFeed(category, region: requestRegion);
      if (requestId != _feedRequestId) return;
      // No shuffle: it threw away YouTube's ranking and moved videos around
      // between refreshes, so a video the user just saw became unfindable.
      trendingVideos = videos;
      if (videos.isEmpty) {
        feedError = 'No videos found. Check internet & pull to retry.';
      }
    } catch (e) {
      if (requestId != _feedRequestId) return;
      feedError = 'Failed to load feed. Pull to retry.\n$e';
      debugPrint('loadTrending: $e');
    } finally {
      if (requestId == _feedRequestId && loadingId == _loadingRequestId) {
        isFeedLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setCategory(String cat) async {
    if (selectedCategory == cat) {
      await loadTrending();
      return;
    }
    selectedCategory = cat;
    trendingVideos = [];
    feedError = null;
    notifyListeners();
    await loadTrending();
  }

  // ---- Shorts ----

  Future<void> loadShorts() async {
    final requestId = ++_shortsRequestId;
    isShortsLoading = true;
    _shortsContinuation = null;
    notifyListeners();
    try {
      // Go through search directly so we get a continuation token back for
      // real pagination (getCategoryFeed discards it).
      final isIn = region.toUpperCase() == 'IN';
      var result = await _client.search(
        isIn ? 'shorts india' : 'shorts',
        params: InnerTubeClient.kFilterShorts,
      );
      if (result.videos.isEmpty) {
        result = await _client.search(
          '#shorts',
          params: InnerTubeClient.kFilterShorts,
        );
      }
      if (requestId != _shortsRequestId) return;
      shortsVideos = result.videos;
      _shortsContinuation = result.continuation;
    } catch (e) {
      debugPrint('loadShorts: $e');
    } finally {
      if (requestId == _shortsRequestId) {
        isShortsLoading = false;
        notifyListeners();
      }
    }
  }

  // ---- YouTube Music ----

  bool isMusicLoading = false;

  Future<void> loadMusic() async {
    final requestId = ++_musicRequestId;
    isMusicLoading = true;
    notifyListeners();
    try {
      final videos = await _client.getCategoryFeed(
        'YouTube Music',
        region: region,
      );
      if (requestId != _musicRequestId) return;
      if (videos.isEmpty) {
        final result = await _client.search('latest music hits 2025');
        if (requestId != _musicRequestId) return;
        musicVideos = result.videos;
      } else {
        musicVideos = videos;
      }
    } catch (e) {
      debugPrint('loadMusic: $e');
    } finally {
      if (requestId == _musicRequestId) {
        isMusicLoading = false;
        notifyListeners();
      }
    }
  }

  /// Loads the next Shorts page using the continuation token.
  ///
  /// This used to re-run the same `'shorts'` query, so the dedupe filter threw
  /// away every result and the feed silently stopped after page 1.
  Future<void> loadMoreShorts() async {
    final token = _shortsContinuation;
    if (isLoadingMoreShorts || token == null || token.isEmpty) return;
    final requestId = _shortsRequestId;
    isLoadingMoreShorts = true;
    try {
      final more = await _client.search('', continuation: token);
      if (requestId != _shortsRequestId) return;
      final seen = shortsVideos.map((v) => v.id).toSet();
      for (final v in more.videos) {
        if (seen.add(v.id)) shortsVideos.add(v);
      }
      // A repeated token would loop forever; only advance on a fresh one.
      _shortsContinuation =
          more.continuation == token ? null : more.continuation;
      notifyListeners();
    } catch (e) {
      debugPrint('loadMoreShorts: $e');
    } finally {
      isLoadingMoreShorts = false;
    }
  }

  // ---- Captions ----

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

  void clearCaptions({bool notify = true}) {
    captionTracks = [];
    captionCues = [];
    if (notify) notifyListeners();
  }

  Future<void> searchVideos(String query) async {
    final normalized = query.trim();
    final requestId = ++_searchRequestId;
    searchQuery = normalized;
    if (normalized.isEmpty) {
      _loadingRequestId++;
      searchResults = [];
      _searchContinuation = null;
      isSearchLoading = false;
      notifyListeners();
      return;
    }
    await storage.addSearchQuery(normalized);
    final updatedHistory = await storage.getSearchHistory();
    if (requestId != _searchRequestId) return;
    searchHistory = updatedHistory;
    final loadingId = ++_loadingRequestId;
    isSearchLoading = true;
    searchError = null;
    _searchContinuation = null;
    notifyListeners();
    try {
      final result = await _client.search(normalized);
      if (requestId != _searchRequestId) return;
      searchResults = result.videos;
      _searchContinuation = result.continuation;
      searchError = null;
    } catch (e) {
      if (requestId != _searchRequestId) return;
      searchError = 'Search failed';
      searchResults = [];
      debugPrint('search: $e');
    } finally {
      if (requestId == _searchRequestId && loadingId == _loadingRequestId) {
        isSearchLoading = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page of search results.
  Future<void> loadMoreSearchResults() async {
    final token = _searchContinuation;
    if (isLoadingMoreSearch || token == null || token.isEmpty) return;
    final requestId = _searchRequestId;
    isLoadingMoreSearch = true;
    notifyListeners();
    try {
      final more = await _client.search(searchQuery, continuation: token);
      if (requestId != _searchRequestId) return;
      final seen = searchResults.map((v) => v.id).toSet();
      for (final v in more.videos) {
        if (seen.add(v.id)) searchResults.add(v);
      }
      _searchContinuation =
          more.continuation == token ? null : more.continuation;
    } catch (e) {
      debugPrint('loadMoreSearchResults: $e');
    } finally {
      if (requestId == _searchRequestId) {
        isLoadingMoreSearch = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchRequestId++;
    _loadingRequestId++;
    isSearchLoading = false;
    searchError = null;
    searchQuery = '';
    searchResults = [];
    _searchContinuation = null;
    notifyListeners();
  }

  Future<void> removeSearchQuery(String query) async {
    await storage.removeSearchQuery(query);
    searchHistory = await storage.getSearchHistory();
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await storage.clearSearchHistory();
    searchHistory = [];
    notifyListeners();
  }

  Future<void> loadVideoDetails(String videoId, {Video? preview}) async {
    final requestId = ++_videoRequestId;
    isPlayerLoading = true;
    playerError = null;
    currentVideo = null;
    relatedVideos = [];
    comments = [];
    sponsorSegments = [];
    dislikeCount = null;
    clearCaptions(notify: false);
    notifyListeners();

    try {
      final details = await _client.getVideoDetails(videoId);
      if (requestId != _videoRequestId) return;
      currentVideo = details;
      isPlayerLoading = false;
      notifyListeners();

      // Playback may start now. History and side-data deliberately continue in
      // the background and every result is guarded by the request ID.
      unawaited(_saveHistory(details, requestId));
      unawaited(_loadVideoSideData(videoId, requestId));
    } catch (e) {
      if (requestId != _videoRequestId) return;
      playerError = 'Could not load video stream.\n$e';
      isPlayerLoading = false;
      debugPrint('loadVideoDetails: $e');
      notifyListeners();
    }
  }

  Future<void> _saveHistory(VideoDetails details, int requestId) async {
    try {
      await storage.addToHistory(
        Video(
          id: details.id,
          title: details.title,
          thumbnailUrl: details.thumbnailUrl,
          channelName: details.channelName,
          channelId: details.channelId,
          viewCount: details.viewCount,
          duration: details.duration,
          publishedAt: details.publishedAt,
        ),
      );
      final value = await storage.getHistory();
      if (requestId == _videoRequestId) {
        history = value;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('history update error: $e');
    }
  }

  Future<void> _loadVideoSideData(String videoId, int requestId) async {
    // Related videos and comments come from the same `next` response, so this
    // is one request instead of two identical ~1 MB downloads.
    Future<void> watchNext() async {
      final value = await _client.getWatchNext(videoId);
      if (requestId == _videoRequestId) {
        relatedVideos = value.related;
        comments = value.comments;
        notifyListeners();
      }
    }

    Future<void> sponsors() async {
      if (!isSponsorBlockEnabled) return;
      final value = await _client.getSponsorSegments(videoId);
      if (requestId == _videoRequestId) {
        sponsorSegments = value;
        notifyListeners();
      }
    }

    Future<void> dislikes() async {
      final value = await _client.getDislikeCount(videoId);
      if (requestId == _videoRequestId) {
        dislikeCount = value;
        notifyListeners();
      }
    }

    Future<void> captions() async {
      // Prefer the tracklist already present in the player response; only
      // fall back to scraping the watch page when it is missing.
      var tracks = currentVideo?.id == videoId
          ? currentVideo?.captionTracks ?? const <CaptionTrack>[]
          : const <CaptionTrack>[];
      if (tracks.isEmpty) {
        tracks = await CaptionService.getTracks(videoId);
      }
      if (requestId != _videoRequestId) return;
      captionTracks = tracks;
      captionCues = [];
      if (tracks.isNotEmpty && isCaptionsEnabled) {
        final track = tracks.firstWhere(
          (t) => t.languageCode == selectedCaptionLanguage,
          orElse: () => tracks.first,
        );
        final cues = await CaptionService.getCues(track.baseUrl);
        if (requestId != _videoRequestId) return;
        captionCues = cues;
        selectedCaptionLanguage = track.languageCode;
      }
      notifyListeners();
    }

    await Future.wait(
      [watchNext(), sponsors(), dislikes(), captions()].map((
        future,
      ) async {
        try {
          await future;
        } catch (e) {
          debugPrint('video side-data error: $e');
        }
      }),
    );
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

    final cached = currentVideo;
    if (cached != null && cached.id == videoId) {
      final muxed = cached.bestMuxedUrl;
      if (isProgressive(muxed)) return muxed;
      if (cached.isLive) throw Exception('Live streams cannot be downloaded');
      // Already-loaded details had no progressive stream; refetching would be
      // 4 more InnerTube calls for the same answer.
      if (cached.formats.isNotEmpty) {
        throw Exception('No downloadable (progressive) stream for this video');
      }
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

  void cancelDownload(String videoId) {
    downloader.cancel(videoId);
    notifyListeners();
  }

  Future<void> downloadVideo(Video video) async {
    if (downloadingIds.contains(video.id)) return;
    downloadingIds.add(video.id);
    downloadProgress[video.id] = 0;
    downloadTitles[video.id] = video.title;
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
    } on DownloadCancelledException {
      // User-initiated: not an error worth surfacing.
      debugPrint('download cancelled: ${video.id}');
    } finally {
      downloadingIds.remove(video.id);
      downloadProgress.remove(video.id);
      downloadTitles.remove(video.id);
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

  /// Persisted subscribe toggle. Returns true when now subscribed.
  Future<bool> toggleSubscription(String channelId) async {
    if (channelId.isEmpty) return false;
    final now = await storage.toggleSubscription(channelId);
    subscriptions = await storage.getSubscriptions();
    notifyListeners();
    return now;
  }

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

  void toggleMusicMode() {
    isMusicMode = !isMusicMode;
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
    if (region == r) return;
    region = r;
    _persistSettings();
    notifyListeners();
    // Region drives every feed query; without a reload the user keeps seeing
    // the previous country's results until they manually pull to refresh.
    loadTrending();
    if (musicVideos.isNotEmpty) loadMusic();
    if (shortsVideos.isNotEmpty) loadShorts();
  }

  List<SponsorSegment> get activeSponsorSegments {
    if (!isSponsorBlockEnabled) return [];
    return sponsorSegments.where((s) => sbEnabled(s.category)).toList();
  }

  @override
  void dispose() {
    _feedRequestId++;
    _searchRequestId++;
    _videoRequestId++;
    _loadingRequestId++;
    _client.dispose();
    downloader.dispose();
    HlsParser.dispose();
    // Was leaked: CaptionService keeps its own shared http.Client, so without
    // this its sockets outlived the provider.
    CaptionService.dispose();
    super.dispose();
  }
}
