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

  bool get isMuxed => hasVideo && hasAudio && url.isNotEmpty;
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

  /// Prefer HLS (adaptive multi-quality) for Auto; else progressive.
  String? get preferredPlayUrl {
    if (hlsUrl != null && hlsUrl!.isNotEmpty) return hlsUrl;
    return bestMuxedUrl;
  }

  String? urlForQuality(String quality) {
    if (quality == 'Auto' || quality == 'Best') return preferredPlayUrl;
    if (quality == 'Audio Only') {
      final audio =
          formats.where((f) => f.isAudioOnly && f.url.isNotEmpty).toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return audio.isNotEmpty ? audio.first.url : preferredPlayUrl;
    }
    // Specific progressive ladder when available
    final target =
        int.tryParse(quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 720;
    final muxed = formats.where((f) => f.isMuxed).toList()
      ..sort((a, b) {
        final da = (a.height - target).abs();
        final db = (b.height - target).abs();
        return da.compareTo(db);
      });
    if (muxed.isNotEmpty) return muxed.first.url;
    // HLS still better than nothing for high qualities
    return preferredPlayUrl;
  }

  List<String> get availableQualities {
    final qs = <String>{};
    for (final f in formats.where((f) => f.isMuxed)) {
      if (f.height >= 1080) {
        qs.add('1080p');
      } else if (f.height >= 720) {
        qs.add('720p');
      } else if (f.height >= 480) {
        qs.add('480p');
      } else if (f.height >= 360) {
        qs.add('360p');
      } else if (f.height > 0) {
        qs.add('${f.height}p');
      }
    }
    final list = qs.toList();
    list.sort((a, b) {
      final ai = int.tryParse(a.replaceAll('p', '')) ?? 0;
      final bi = int.tryParse(b.replaceAll('p', '')) ?? 0;
      return bi.compareTo(ai);
    });
    if (hlsUrl != null && hlsUrl!.isNotEmpty && !list.contains('1080p')) {
      // HLS typically includes 720/1080
      if (!list.contains('720p')) list.insert(0, '720p');
    }
    return ['Auto', ...list, 'Audio Only'];
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
