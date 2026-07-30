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
  });

  bool get isMuxed => url.isNotEmpty && hasVideo && hasAudio && !isAudioOnly && !isVideoOnly;
}

class VideoDetails extends Video {
  final List<VideoFormat> formats;
  final String? hlsUrl;
  final String? dashUrl;
  final int likeCount;
  final bool isLive;

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
    this.formats = const [],
    this.hlsUrl,
    this.dashUrl,
    this.likeCount = 0,
    this.isLive = false,
  });

  /// Best progressive (muxed audio+video) URL for instant play.
  String? get bestMuxedUrl {
    final muxed = formats.where((f) => f.isMuxed).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    if (muxed.isNotEmpty) return muxed.first.url;
    for (final f in formats) {
      if (f.url.isNotEmpty && !f.isAudioOnly && f.hasVideo) return f.url;
    }
    for (final f in formats) {
      if (f.url.isNotEmpty && !f.isAudioOnly) return f.url;
    }
    return null;
  }

  /// Auto: prefer HLS (adaptive high quality). Explicit ladder uses progressive when available.
  String? get preferredPlayUrl {
    if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
    return bestMuxedUrl;
  }

  /// Progressive-only best URL (for downloads / fallback).
  String? get progressiveUrl => bestMuxedUrl;

  String? urlForQuality(String quality) {
    final q = quality.trim();
    if (q == 'Auto' || q == 'Best' || q == 'Auto (HLS)') {
      return preferredPlayUrl;
    }
    if (q == 'Audio Only') {
      final audio =
          formats.where((f) => f.isAudioOnly && f.url.isNotEmpty).toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      if (audio.isNotEmpty) return audio.first.url;
      return preferredPlayUrl;
    }
    // Specific height — try progressive muxed matching height, else HLS (player adaptive)
    final target = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (target > 0) {
      final muxed = formats.where((f) => f.isMuxed && f.url.isNotEmpty).toList();
      // exact or nearest progressive
      final exact = muxed.where((f) => f.height == target).toList();
      if (exact.isNotEmpty) return exact.first.url;
      if (muxed.isNotEmpty) {
        muxed.sort((a, b) => (a.height - target).abs().compareTo((b.height - target).abs()));
        // Only use progressive if reasonably close (within 120p) otherwise HLS
        if ((muxed.first.height - target).abs() <= 120) {
          return muxed.first.url;
        }
      }
      // High qualities (720+) almost always need HLS on mobile clients
      if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
      return bestMuxedUrl;
    }
    return preferredPlayUrl;
  }

  List<String> get availableQualities {
    final qs = <String>{};
    // From progressive
    for (final f in formats.where((f) => f.isMuxed || (f.hasVideo && !f.isAudioOnly))) {
      if (f.height >= 2160) qs.add('2160p');
      else if (f.height >= 1440) qs.add('1440p');
      else if (f.height >= 1080) qs.add('1080p');
      else if (f.height >= 720) qs.add('720p');
      else if (f.height >= 480) qs.add('480p');
      else if (f.height >= 360) qs.add('360p');
      else if (f.height >= 240) qs.add('240p');
      else if (f.height >= 144) qs.add('144p');
    }
    // HLS unlocks full ladder even when progressive is only 360p
    if (hlsUrl != null && hlsUrl!.isNotEmpty) {
      qs.addAll(['144p', '240p', '360p', '480p', '720p', '1080p']);
      // common extras
      qs.add('1440p');
      qs.add('2160p');
    }
    final order = ['2160p', '1440p', '1080p', '720p', '480p', '360p', '240p', '144p'];
    final list = order.where(qs.contains).toList();
    return ['Auto (HLS)', ...list, 'Audio Only'];
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
