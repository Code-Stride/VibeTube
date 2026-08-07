import 'dart:async';
import 'package:flutter/material.dart';
import '../api/innertube_client.dart';
import '../models/video.dart';
import '../utils/theme.dart';
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

  /// Cursor for the "Next" / auto-advance button in the player.
  ///
  /// It can't live on PlayerScreen's State: tapping Next does a
  /// `Navigator.pushReplacement`, which disposes the current State and
  /// creates a fresh one whose cursor is 0 — so the second tap always
  /// reopened relatedVideos[0] and the list never advanced. Living on the
  /// provider keeps it alive across replacements; [loadVideoDetails] resets
  /// it for each freshly opened video.
  int nextRelatedIndex = 0;

  List<String> searchHistory = [];

  VideoDetails? currentVideo;
  int? dislikeCount;

  /// Home / category feed loading. Search has its own [isSearching] flag:
  /// sharing one bool made the Search tab spin while the Home feed refreshed
  /// (and vice versa), and the shared `_loadingRequestId` guard could leave a
  /// spinner up forever when the two overlapped.
  bool isLoading = false;
  bool isSearching = false;
  bool isPlayerLoading = false;
  bool isShortsLoading = false;
  bool isLoadingMoreFeed = false;
  bool isLoadingMoreSearch = false;
  String? error;
  String? searchError;
  String? playerError;
  String searchQuery = '';
  String selectedCategory = 'All';

  // Continuation tokens for infinite scroll. Null means "no more pages".
  String? _feedContinuation;
  String? _searchContinuation;
  String? _shortsContinuation;
  bool get hasMoreFeed => _feedContinuation != null;
  bool get hasMoreSearch => _searchContinuation != null;

  // Monotonic request IDs prevent stale async responses from overwriting
  // newer user intent (fast searches, category changes, and A→B navigation).
  int _feedRequestId = 0;
  int _searchRequestId = 0;
  int _videoRequestId = 0;
  int _shortsRequestId = 0;
  int _musicRequestId = 0;

  // download progress videoId -> 0..1
  final Map<String, double> downloadProgress = {};
  final Set<String> downloadingIds = {};

  bool isDarkMode = true;
  bool isMusicMode = false;
  /// Ad-free playback is a *property of the InnerTube clients* this app uses
  /// (IOS / ANDROID / MEDIACONNECT never return ad breaks), not something the
  /// app can switch on and off. The field is kept so existing preferences
  /// still load, but the Settings row is now an always-on status indicator
  /// instead of a toggle that silently did nothing.
  final bool isAdBlockEnabled = true;
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
    isMusicMode = s['isMusicMode'] ?? false;
    isSponsorBlockEnabled = s['isSponsorBlockEnabled'] ?? true;
    isBackgroundPlayEnabled = s['isBackgroundPlayEnabled'] ?? true;
    isAutoPipEnabled = s['isAutoPipEnabled'] ?? true;
    // Must match the field initialiser above. These disagreed ('Auto (HLS)'
    // vs '1080p'), so a fresh install silently defaulted to a locked 1080p
    // that many videos cannot serve.
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
    notifyListeners();
    loadTrending();
    checkUpdate();
  }

  Future<void> _persistSettings() async {
    await storage.saveSettings({
      'isDarkMode': isDarkMode,
      'isMusicMode': isMusicMode,
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
    final requestId = ++_feedRequestId;
    final category = selectedCategory;
    final requestRegion = region;
    isLoading = true;
    error = null;
    _feedContinuation = null;
    notifyListeners();
    try {
      final List<Video> videos;
      if (category == 'All') {
        videos = await _client.getTrending(region: requestRegion);
        _feedContinuation = null; // trending is assembled from several queries
      } else {
        final page = await _client.getCategoryPage(category, region: requestRegion);
        videos = page.videos;
        _feedContinuation = page.continuation;
      }
      if (requestId != _feedRequestId) return;
      // No shuffle: YouTube already ranks these, and re-shuffling on every
      // rebuild/refresh meant the same videos jumped around the feed and a
      // user could never scroll back to something they just saw.
      trendingVideos = videos;
      if (videos.isEmpty) {
        error = 'No videos found. Check internet & pull to retry.';
      }
    } catch (e) {
      if (requestId != _feedRequestId) return;
      error = 'Failed to load feed. Pull to retry.\n$e';
      debugPrint('loadTrending: $e');
    } finally {
      if (requestId == _feedRequestId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page of the current category feed.
  Future<void> loadMoreFeed() async {
    final token = _feedContinuation;
    if (token == null || isLoadingMoreFeed || isLoading) return;
    final requestId = _feedRequestId;
    final category = selectedCategory;
    isLoadingMoreFeed = true;
    notifyListeners();
    try {
      final page = await _client.getCategoryPage(
        category,
        region: region,
        continuation: token,
      );
      if (requestId != _feedRequestId) return;
      final seen = trendingVideos.map((v) => v.id).toSet();
      for (final v in page.videos) {
        if (v.id.isNotEmpty && seen.add(v.id)) trendingVideos.add(v);
      }
      // A page that yields nothing new, or repeats the same token, ends the
      // feed rather than looping forever.
      final next = page.continuation;
      _feedContinuation =
          (page.videos.isEmpty || next == null || next == token) ? null : next;
    } catch (e) {
      debugPrint('loadMoreFeed: $e');
      _feedContinuation = null;
    } finally {
      if (requestId == _feedRequestId) {
        isLoadingMoreFeed = false;
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
    error = null;
    notifyListeners();
    // Coming back to 'All' needs the music shelf populated again.
    if (cat == 'All' && musicVideos.isEmpty && !isMusicLoading) {
      unawaited(loadMusic());
    }
    await loadTrending();
  }

  // ---- Shorts ----

  Future<void> loadShorts() async {
    // Guarded like the other feeds: two overlapping loads (tab re-entry +
    // pull-to-refresh) used to race, and whichever finished last won even if
    // it was the older request.
    final requestId = ++_shortsRequestId;
    isShortsLoading = true;
    _shortsContinuation = null;
    notifyListeners();
    try {
      var page = await _client.getCategoryPage('Shorts', region: region);
      if (page.videos.isEmpty) {
        page = await _client.search(
          '#shorts',
          params: InnerTubeClient.kFilterShorts,
          region: region,
        );
      }
      if (requestId != _shortsRequestId) return;
      shortsVideos = page.videos;
      _shortsContinuation = page.continuation;
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

  /// Selected chip in Music Mode. These chips used to be decorative
  /// (`selected: false, onSelected: (_) {}`) — tapping any of them did
  /// nothing at all.
  String selectedMusicCategory = 'All';

  /// Maps a Music Mode chip to a search query.
  String _musicQuery(String category) {
    final isIn = region.toUpperCase() == 'IN';
    switch (category.trim().toLowerCase()) {
      case 'all':
        return isIn ? 'latest music india 2025' : 'music hits 2025';
      case 'trending':
        return isIn ? 'trending songs india' : 'trending songs';
      case 'new releases':
        return isIn ? 'new song releases india' : 'new music releases';
      case 'bollywood':
        return 'bollywood songs';
      case 'pop':
        return 'pop music hits';
      case 'hip-hop':
        return isIn ? 'indian hip hop' : 'hip hop hits';
      case 'r&b':
        return 'rnb songs';
      case 'classical':
        return isIn ? 'indian classical music' : 'classical music';
      case 'devotional':
        return isIn ? 'bhajan devotional songs' : 'devotional music';
      case 'podcasts':
        return isIn ? 'podcast india' : 'podcast';
      default:
        return category;
    }
  }

  Future<void> setMusicCategory(String category) async {
    if (selectedMusicCategory == category) return;
    selectedMusicCategory = category;
    musicVideos = [];
    notifyListeners();
    await loadMusic();
  }

  Future<void> loadMusic() async {
    final requestId = ++_musicRequestId;
    isMusicLoading = true;
    notifyListeners();
    try {
      final query = _musicQuery(selectedMusicCategory);
      var videos = (await _client.search(query, region: region)).videos;
      if (videos.isEmpty) {
        videos = await _client.getCategoryFeed('YouTube Music', region: region);
      }
      if (requestId != _musicRequestId) return;
      musicVideos = videos;
    } catch (e) {
      debugPrint('loadMusic: $e');
    } finally {
      if (requestId == _musicRequestId) {
        isMusicLoading = false;
        notifyListeners();
      }
    }
  }

  bool _loadingMoreShorts = false;

  /// Appends the next Shorts page.
  ///
  /// This used to re-run the *same* `'shorts'` query every time, so every
  /// result was already in `seen` and nothing was ever added — the Shorts feed
  /// dead-ended at roughly 20 videos. It now follows the continuation token.
  Future<void> loadMoreShorts() async {
    final token = _shortsContinuation;
    if (token == null || _loadingMoreShorts) return;
    final requestId = _shortsRequestId;
    _loadingMoreShorts = true;
    try {
      final more = await _client.search(
        'shorts',
        params: InnerTubeClient.kFilterShorts,
        region: region,
        continuation: token,
      );
      if (requestId != _shortsRequestId) return;
      final seen = shortsVideos.map((v) => v.id).toSet();
      var added = 0;
      for (final v in more.videos) {
        if (v.id.isNotEmpty && seen.add(v.id)) {
          shortsVideos.add(v);
          added++;
        }
      }
      final next = more.continuation;
      _shortsContinuation = (added == 0 || next == null || next == token) ? null : next;
      notifyListeners();
    } catch (e) {
      debugPrint('loadMoreShorts: $e');
      _shortsContinuation = null;
    } finally {
      _loadingMoreShorts = false;
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

  void clearCaptions({bool notify = true}) {
    captionTracks = [];
    captionCues = [];
    if (notify) notifyListeners();
  }

  Future<void> searchVideos(String query) async {
    final normalized = query.trim();
    final requestId = ++_searchRequestId;
    searchQuery = normalized;
    _searchContinuation = null;
    if (normalized.isEmpty) {
      searchResults = [];
      isSearching = false;
      searchError = null;
      notifyListeners();
      return;
    }
    await storage.addSearchQuery(normalized);
    final updatedHistory = await storage.getSearchHistory();
    if (requestId != _searchRequestId) return;
    searchHistory = updatedHistory;
    isSearching = true;
    searchError = null;
    notifyListeners();
    try {
      final result = await _client.search(normalized, region: region);
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
      if (requestId == _searchRequestId) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page of search results (infinite scroll).
  Future<void> loadMoreSearch() async {
    final token = _searchContinuation;
    if (token == null || isLoadingMoreSearch || isSearching) return;
    final requestId = _searchRequestId;
    isLoadingMoreSearch = true;
    notifyListeners();
    try {
      final result = await _client.search(
        searchQuery,
        region: region,
        continuation: token,
      );
      if (requestId != _searchRequestId) return;
      final seen = searchResults.map((v) => v.id).toSet();
      var added = 0;
      for (final v in result.videos) {
        if (v.id.isNotEmpty && seen.add(v.id)) {
          searchResults.add(v);
          added++;
        }
      }
      final next = result.continuation;
      _searchContinuation =
          (added == 0 || next == null || next == token) ? null : next;
    } catch (e) {
      debugPrint('loadMoreSearch: $e');
      _searchContinuation = null;
    } finally {
      if (requestId == _searchRequestId) {
        isLoadingMoreSearch = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    _searchRequestId++;
    isSearching = false;
    isLoadingMoreSearch = false;
    searchQuery = '';
    searchResults = [];
    searchError = null;
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
    // A new video was opened (not auto-advanced into): restart the
    // related-video cursor so the first "Next" picks relatedVideos[0].
    nextRelatedIndex = 0;
    clearCaptions(notify: false);
    notifyListeners();

    try {
      final details = await _client.getVideoDetails(videoId, region: region);
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
    Future<void> related() async {
      final value = await _client.getRelatedVideos(videoId);
      if (requestId == _videoRequestId) {
        relatedVideos = value;
        notifyListeners();
      }
    }

    Future<void> commentData() async {
      final value = await _client.getComments(videoId);
      if (requestId == _videoRequestId) {
        comments = value;
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
      // The player response already carried the track list in almost every
      // case; only fall back to scraping the watch page when it did not.
      var tracks = currentVideo?.id == videoId
          ? (currentVideo?.captionTracks ?? const <CaptionTrack>[])
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
      [related(), commentData(), sponsors(), dislikes(), captions()].map((
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

    if (currentVideo?.id == videoId) {
      final muxed = currentVideo?.bestMuxedUrl;
      if (isProgressive(muxed)) return muxed;
    }
    final d = await _client.getVideoDetails(videoId, region: region);
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
    // Applied here rather than in MaterialApp's builder: this is the only
    // place the value changes, and calling it during build issued a platform
    // channel message on every unrelated notifyListeners().
    AppTheme.applySystemUi(isDarkMode);
    _persistSettings();
    notifyListeners();
  }

  void toggleMusicMode() {
    isMusicMode = !isMusicMode;
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
    // Cached feeds belong to the old region; refetch so the change is visible
    // immediately instead of on the next cold start.
    trendingVideos = [];
    musicVideos = [];
    shortsVideos = [];
    loadTrending();
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
    _shortsRequestId++;
    _musicRequestId++;
    _client.dispose();
    downloader.dispose();
    HlsParser.dispose();
    // Was leaked: CaptionService keeps its own shared http.Client, so without
    // this its sockets outlived the provider.
    CaptionService.dispose();
    super.dispose();
  }
}
