class Video {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String channelName;
  final String channelId;
  final String channelAvatar;
  final int viewCount;
  final Duration duration;
  final String publishedAt;
  final String description;
  final String localPath;
  final bool isLive;
  final bool isShort;

  const Video({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    this.channelName = '',
    this.channelId = '',
    this.channelAvatar = '',
    this.viewCount = 0,
    this.duration = Duration.zero,
    this.publishedAt = '',
    this.description = '',
    this.localPath = '',
    this.isLive = false,
    this.isShort = false,
  });

  String get formattedViewCount {
    if (viewCount >= 1000000000) {
      return '${(viewCount / 1000000000).toStringAsFixed(1)}B';
    }
    if (viewCount >= 1000000) {
      return '${(viewCount / 1000000).toStringAsFixed(1)}M';
    }
    if (viewCount >= 1000) {
      return '${(viewCount / 1000).toStringAsFixed(1)}K';
    }
    return viewCount.toString();
  }

  String get formattedDuration {
    if (duration == Duration.zero) return '';
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'channelName': channelName,
        'channelId': channelId,
        'channelAvatar': channelAvatar,
        'viewCount': viewCount,
        'duration': duration.inSeconds,
        'publishedAt': publishedAt,
        'description': description,
        'localPath': localPath,
        'isLive': isLive,
        'isShort': isShort,
      };

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        thumbnailUrl: j['thumbnailUrl'] ?? '',
        channelName: j['channelName'] ?? '',
        channelId: j['channelId'] ?? '',
        channelAvatar: j['channelAvatar'] ?? '',
        viewCount: j['viewCount'] ?? 0,
        duration: Duration(seconds: j['duration'] ?? 0),
        publishedAt: j['publishedAt'] ?? '',
        description: j['description'] ?? '',
        localPath: j['localPath'] ?? '',
        isLive: j['isLive'] == true,
        isShort: j['isShort'] == true,
      );

  Video copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    String? channelName,
    String? channelId,
    String? channelAvatar,
    int? viewCount,
    Duration? duration,
    String? publishedAt,
    String? description,
    String? localPath,
    bool? isLive,
    bool? isShort,
  }) {
    return Video(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      channelName: channelName ?? this.channelName,
      channelId: channelId ?? this.channelId,
      channelAvatar: channelAvatar ?? this.channelAvatar,
      viewCount: viewCount ?? this.viewCount,
      duration: duration ?? this.duration,
      publishedAt: publishedAt ?? this.publishedAt,
      description: description ?? this.description,
      localPath: localPath ?? this.localPath,
      isLive: isLive ?? this.isLive,
      isShort: isShort ?? this.isShort,
    );
  }
}

class VideoFormat {
  final String url;
  final String quality;
  final String mimeType;
  final int width;
  final int height;
  final int bitrate;
  final int itag;
  final bool isVideoOnly;
  final bool isAudioOnly;
  final bool hasAudio;
  final bool hasVideo;

  /// User-Agent of the InnerTube client this URL was minted for.
  ///
  /// googlevideo binds a stream URL to the requesting client, so replaying an
  /// IOS URL with an Android UA is a 403. Recorded so playback can present the
  /// right UA first instead of brute-forcing a header ladder.
  final String clientUserAgent;

  const VideoFormat({
    required this.url,
    required this.quality,
    this.mimeType = '',
    this.width = 0,
    this.height = 0,
    this.bitrate = 0,
    this.itag = 0,
    this.isVideoOnly = false,
    this.isAudioOnly = false,
    this.hasAudio = false,
    this.hasVideo = false,
    this.clientUserAgent = '',
  });

  bool get isMuxed =>
      url.isNotEmpty && hasVideo && hasAudio && !isAudioOnly && !isVideoOnly;
}

class VideoDetails extends Video {
  final List<VideoFormat> formats;
  final String? hlsUrl;
  final String? dashUrl;
  final int likeCount;
  /// height (e.g. 720) -> specific HLS media playlist URL (muxed A/V)
  final Map<int, String> hlsVariants;
  /// height -> progressive muxed mp4 when available
  final Map<int, String> progressiveByHeight;

  /// Caption tracks that arrived with the player response, so the UI does not
  /// need a separate watch-page scrape to discover them.
  final List<CaptionTrack> captionTracks;

  const VideoDetails({
    required super.id,
    required super.title,
    super.description = '',
    super.channelName = '',
    super.channelId = '',
    super.channelAvatar = '',
    super.viewCount = 0,
    super.duration = Duration.zero,
    super.thumbnailUrl = '',
    super.publishedAt = '',
    super.localPath = '',
    super.isLive = false,
    super.isShort = false,
    this.formats = const [],
    this.hlsUrl,
    this.dashUrl,
    this.likeCount = 0,
    this.hlsVariants = const {},
    this.progressiveByHeight = const {},
    this.captionTracks = const [],
  });

  /// Best progressive (muxed audio+video) URL.
  /// UA that [url] was issued to, or null when unknown.
  String? userAgentForUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    for (final f in formats) {
      if (f.url == url && f.clientUserAgent.isNotEmpty) {
        return f.clientUserAgent;
      }
    }
    return null;
  }

  String? get bestMuxedUrl {
    if (progressiveByHeight.isNotEmpty) {
      final h = progressiveByHeight.keys.toList()..sort((a, b) => b.compareTo(a));
      return progressiveByHeight[h.first];
    }
    final muxed = formats.where((f) => f.isMuxed).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    if (muxed.isNotEmpty) return muxed.first.url;
    for (final f in formats) {
      if (f.url.isNotEmpty && !f.isAudioOnly && f.hasVideo) return f.url;
    }
    return null;
  }

  /// Auto: best quality HLS variant → master HLS → best progressive.
  String? get preferredPlayUrl {
    if (hlsVariants.isNotEmpty) {
      final h = hlsVariants.keys.toList()..sort((a, b) => b.compareTo(a));
      return hlsVariants[h.first];
    }
    if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
    return bestMuxedUrl;
  }

  String? get progressiveUrl => bestMuxedUrl;

  /// Resolve a concrete playable URL for the chosen quality label.
  String? urlForQuality(String quality) {
    final q = quality.trim();
    if (q == 'Auto' || q == 'Best') {
      return preferredPlayUrl;
    }
    if (q == 'Auto (HLS)') {
      // Auto (HLS) = adaptive master playlist (for adaptive streaming)
      if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
      return preferredPlayUrl;
    }
    if (q == 'Audio Only') {
      final audio =
          formats.where((f) => f.isAudioOnly && f.url.isNotEmpty).toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      if (audio.isNotEmpty) return audio.first.url;
      // lowest hls as audio-ish fallback
      if (hlsVariants.isNotEmpty) {
        final h = hlsVariants.keys.toList()..sort();
        return hlsVariants[h.first];
      }
      return preferredPlayUrl;
    }

    final target = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (target <= 0) return preferredPlayUrl;

    // 1) Exact HLS variant for this height (best — real quality lock)
    if (hlsVariants.containsKey(target)) {
      return hlsVariants[target];
    }
    // nearest HLS height
    if (hlsVariants.isNotEmpty) {
      final heights = hlsVariants.keys.toList()
        ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
      return hlsVariants[heights.first];
    }

    // 2) Progressive muxed map
    if (progressiveByHeight.containsKey(target)) {
      return progressiveByHeight[target];
    }
    if (progressiveByHeight.isNotEmpty) {
      final heights = progressiveByHeight.keys.toList()
        ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
      return progressiveByHeight[heights.first];
    }

    // 3) formats list muxed
    final muxed = formats.where((f) => f.isMuxed && f.url.isNotEmpty).toList();
    if (muxed.isNotEmpty) {
      muxed.sort((a, b) =>
          (a.height - target).abs().compareTo((b.height - target).abs()));
      return muxed.first.url;
    }

    // 4) master HLS / anything
    if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
    return bestMuxedUrl;
  }

  List<String> get availableQualities {
    final heights = <int>{
      ...hlsVariants.keys,
      ...progressiveByHeight.keys,
    };
    for (final f in formats.where((f) => f.isMuxed && f.height > 0)) {
      heights.add(f.height);
    }

    String labelFor(int h) {
      if (h >= 2160) return '2160p';
      if (h >= 1440) return '1440p';
      if (h >= 1080) return '1080p';
      if (h >= 720) return '720p';
      if (h >= 480) return '480p';
      if (h >= 360) return '360p';
      if (h >= 240) return '240p';
      if (h >= 144) return '144p';
      return '${h}p';
    }

    // Normalize to standard ladder labels (unique)
    final labels = <String>{};
    for (final h in heights) {
      labels.add(labelFor(h));
    }

    // When only a master HLS playlist is known (no parsed variants) `labels`
    // stays empty on purpose: the list below then collapses to just
    // "Auto (HLS)" + "Audio Only" rather than advertising phantom heights the
    // player cannot actually lock to.
    const order = [
      '2160p',
      '1440p',
      '1080p',
      '720p',
      '480p',
      '360p',
      '240p',
      '144p'
    ];
    final list = order.where(labels.contains).toList();
    return ['Auto (HLS)', ...list, 'Audio Only'];
  }

  /// Whether a quality can genuinely be locked (a concrete stream URL exists
  /// for that height, not just an adaptive master playlist).
  ///
  /// This used to fall back to `hlsUrl != null`, which reported *every* height
  /// as lockable whenever a master playlist existed. The UI then said
  /// "Tap to lock · HLS" for 2160p on a 480p video and quietly played
  /// something else.
  bool canLockQuality(String quality) {
    final q = quality.trim();
    if (q.startsWith('Auto') || q == 'Best' || q == 'Audio Only') return true;
    final target = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (target <= 0) return false;
    if (hlsVariants.containsKey(target)) return true;
    if (progressiveByHeight.containsKey(target)) return true;
    // nearest within 20p from known heights (1080 vs 1088 etc.)
    for (final h in [...hlsVariants.keys, ...progressiveByHeight.keys]) {
      if ((h - target).abs() <= 20) return true;
    }
    return formats.any((f) => f.isMuxed && (f.height - target).abs() <= 20);
  }

  VideoDetails copyWithStreams({
    Map<int, String>? hlsVariants,
    Map<int, String>? progressiveByHeight,
    String? hlsUrl,
    List<VideoFormat>? formats,
  }) {
    return VideoDetails(
      id: id,
      title: title,
      description: description,
      channelName: channelName,
      channelId: channelId,
      channelAvatar: channelAvatar,
      viewCount: viewCount,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      publishedAt: publishedAt,
      localPath: localPath,
      isLive: isLive,
      isShort: isShort,
      formats: formats ?? this.formats,
      hlsUrl: hlsUrl ?? this.hlsUrl,
      dashUrl: dashUrl,
      likeCount: likeCount,
      hlsVariants: hlsVariants ?? this.hlsVariants,
      progressiveByHeight: progressiveByHeight ?? this.progressiveByHeight,
      captionTracks: captionTracks,
    );
  }
}

class Comment {
  final String id;
  final String author;
  final String authorAvatar;
  final String text;
  final int likeCount;
  final String publishedAt;

  const Comment({
    required this.id,
    required this.author,
    this.authorAvatar = '',
    required this.text,
    this.likeCount = 0,
    this.publishedAt = '',
  });
}

class SearchResult {
  final List<Video> videos;
  final String? continuation;
  const SearchResult({required this.videos, this.continuation});
}

class SponsorSegment {
  final double start;
  final double end;
  final String category;
  const SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
  });
}

class AppUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.releaseNotes = '',
    this.downloadUrl = '',
    required this.hasUpdate,
  });
}


/// A single timed caption line.
///
/// Lives in models (rather than CaptionService) so VideoDetails can carry the
/// caption track list that arrives with the InnerTube player response.
class CaptionCue {
  final Duration start;
  final Duration end;
  final String text;

  const CaptionCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// One selectable caption track for a video.
class CaptionTrack {
  final String languageCode;
  final String name;
  final String baseUrl;
  final bool isAutoGenerated;

  const CaptionTrack({
    required this.languageCode,
    required this.name,
    required this.baseUrl,
    this.isAutoGenerated = false,
  });
}
