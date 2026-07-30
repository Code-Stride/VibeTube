package com.blazenxt.vibetube.data.repository

import com.blazenxt.vibetube.data.api.YouTubeApiService
import com.blazenxt.vibetube.data.api.PipedApiService
import com.blazenxt.vibetube.data.model.*
import com.blazenxt.vibetube.sponsorblock.SponsorBlockApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class YouTubeRepository @Inject constructor(
    private val youTubeApi: YouTubeApiService,
    private val pipedApi: PipedApiService,
    private val sponsorBlockApi: SponsorBlockApi
) {
    
    suspend fun getTrendingVideos(): List<Video> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getTrending("US")
            response.map { it.toVideo() }
        } catch (e: Exception) {
            Timber.e(e, "Failed to fetch trending")
            emptyList()
        }
    }

    suspend fun searchVideos(query: String, nextPageToken: String? = null): SearchResult = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.search(query, "videos", nextPageToken)
            SearchResult(
                videos = response.items.map { it.toVideo() },
                nextPageToken = response.nextpage
            )
        } catch (e: Exception) {
            Timber.e(e, "Search failed for: $query")
            SearchResult(emptyList())
        }
    }

    suspend fun getVideoStreams(videoId: String): List<VideoStream> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getStreams(videoId)
            val streams = mutableListOf<VideoStream>()
            
            // Video streams
            response.videoStreams?.forEach { stream ->
                streams.add(
                    VideoStream(
                        url = stream.url ?: "",
                        quality = stream.quality ?: "Unknown",
                        format = stream.mimeType ?: "video/mp4",
                        width = stream.width ?: 0,
                        height = stream.height ?: 0,
                        fps = stream.fps ?: 30,
                        bitrate = stream.bitrate ?: 0,
                        isVideoOnly = stream.videoOnly ?: false
                    )
                )
            }
            
            // Audio streams
            response.audioStreams?.forEach { stream ->
                streams.add(
                    VideoStream(
                        url = stream.url ?: "",
                        quality = stream.quality ?: "Unknown",
                        format = stream.mimeType ?: "audio/mp4",
                        bitrate = stream.bitrate ?: 0,
                        isAudioOnly = true
                    )
                )
            }
            
            streams.sortedByDescending { it.height }
        } catch (e: Exception) {
            Timber.e(e, "Failed to get streams for: $videoId")
            emptyList()
        }
    }

    suspend fun getVideoInfo(videoId: String): Video? = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getStreams(videoId)
            Video(
                id = videoId,
                title = response.title ?: "",
                description = response.description ?: "",
                thumbnailUrl = response.thumbnailUrl ?: "",
                channelName = response.uploader ?: "",
                channelId = response.uploaderUrl ?: "",
                channelAvatar = response.uploaderAvatar ?: "",
                viewCount = response.views ?: 0,
                likeCount = response.likes ?: 0,
                duration = response.duration?.toLong() ?: 0,
                publishedAt = response.uploadDate ?: "",
                url = "https://youtube.com/watch?v=$videoId"
            )
        } catch (e: Exception) {
            Timber.e(e, "Failed to get video info for: $videoId")
            null
        }
    }

    suspend fun getComments(videoId: String): List<Comment> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getComments(videoId)
            response.comments.map { comment ->
                Comment(
                    id = comment.commentId ?: "",
                    author = comment.author ?: "",
                    authorAvatar = comment.thumbnail ?: "",
                    text = comment.commentText ?: "",
                    likeCount = comment.likeCount ?: 0,
                    publishedAt = comment.publishedText ?: "",
                    replyCount = comment.replyCount ?: 0,
                    isHearted = comment.hearted ?: false
                )
            }
        } catch (e: Exception) {
            Timber.e(e, "Failed to get comments for: $videoId")
            emptyList()
        }
    }

    suspend fun getRelatedVideos(videoId: String): List<Video> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getStreams(videoId)
            response.relatedStreams?.map { it.toVideo() } ?: emptyList()
        } catch (e: Exception) {
            Timber.e(e, "Failed to get related videos for: $videoId")
            emptyList()
        }
    }

    suspend fun getSponsorBlockSegments(videoId: String): List<SponsorSegment> = withContext(Dispatchers.IO) {
        try {
            sponsorBlockApi.getSegments(videoId)
        } catch (e: Exception) {
            Timber.e(e, "Failed to get SponsorBlock segments")
            emptyList()
        }
    }

    suspend fun getVideosByCategory(category: String): List<Video> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.search(category, "videos", null)
            response.items.map { it.toVideo() }
        } catch (e: Exception) {
            Timber.e(e, "Failed to get videos for category: $category")
            emptyList()
        }
    }

    suspend fun getChannelVideos(channelId: String): List<Video> = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getChannel(channelId)
            response.relatedStreams?.map { it.toVideo() } ?: emptyList()
        } catch (e: Exception) {
            Timber.e(e, "Failed to get channel videos: $channelId")
            emptyList()
        }
    }

    suspend fun getPlaylist(playlistId: String): Playlist = withContext(Dispatchers.IO) {
        try {
            val response = pipedApi.getPlaylist(playlistId)
            Playlist(
                id = playlistId,
                title = response.name ?: "",
                description = response.description ?: "",
                thumbnailUrl = response.thumbnailUrl ?: "",
                channelName = response.uploader ?: "",
                videoCount = response.videos ?: 0,
                videos = response.relatedStreams?.map { it.toVideo() } ?: emptyList()
            )
        } catch (e: Exception) {
            Timber.e(e, "Failed to get playlist: $playlistId")
            Playlist(id = playlistId, title = "Unknown Playlist")
        }
    }
}
