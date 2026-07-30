package com.blazenxt.vibetube.data.api

import com.blazenxt.vibetube.data.model.*
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

interface PipedApiService {

    @GET("trending")
    suspend fun getTrending(
        @Query("region") region: String = "US"
    ): List<PipedVideoResponse>

    @GET("streams/{videoId}")
    suspend fun getStreams(
        @Path("videoId") videoId: String
    ): PipedStreamResponse

    @GET("search")
    suspend fun search(
        @Query("q") query: String,
        @Query("filter") filter: String = "videos",
        @Query("nextpage") nextpage: String? = null
    ): PipedSearchResponse

    @GET("comments/{videoId}")
    suspend fun getComments(
        @Path("videoId") videoId: String
    ): PipedCommentsResponse

    @GET("channel/{channelId}")
    suspend fun getChannel(
        @Path("channelId") channelId: String
    ): PipedChannelResponse

    @GET("playlists/{playlistId}")
    suspend fun getPlaylist(
        @Path("playlistId") playlistId: String
    ): PipedPlaylistResponse
}

// Piped API Response Models
data class PipedVideoResponse(
    val url: String?,
    val title: String?,
    val thumbnail: String?,
    val uploaderName: String?,
    val uploaderUrl: String?,
    val uploaderAvatar: String?,
    val views: Long?,
    val uploaded: Long?,
    val uploadedDate: String?,
    val duration: Int?,
    val isShort: Boolean = false
) {
    fun toVideo(): Video {
        val videoId = url?.substringAfter("/watch?v=") ?: ""
        return Video(
            id = videoId,
            title = title ?: "",
            thumbnailUrl = thumbnail ?: "",
            channelName = uploaderName ?: "",
            channelId = uploaderUrl ?: "",
            channelAvatar = uploaderAvatar ?: "",
            viewCount = views ?: 0,
            duration = duration?.toLong() ?: 0,
            publishedAt = uploadedDate ?: "",
            url = "https://youtube.com/watch?v=$videoId"
        )
    }
}

data class PipedStreamResponse(
    val title: String?,
    val description: String?,
    val uploadDate: String?,
    val uploader: String?,
    val uploaderUrl: String?,
    val uploaderAvatar: String?,
    val thumbnailUrl: String?,
    val views: Long?,
    val likes: Long?,
    val dislikes: Long?,
    val duration: Int?,
    val hls: String?,
    val dash: String?,
    val videoStreams: List<PipedStream>?,
    val audioStreams: List<PipedStream>?,
    val relatedStreams: List<PipedVideoResponse>?
)

data class PipedStream(
    val url: String?,
    val format: String?,
    val quality: String?,
    val mimeType: String?,
    val width: Int?,
    val height: Int?,
    val fps: Int?,
    val bitrate: Long?,
    val videoOnly: Boolean? = false,
    val audioOnly: Boolean? = false
)

data class PipedSearchResponse(
    val items: List<PipedVideoResponse>,
    val nextpage: String?,
    val suggestion: String?,
    val corrected: Boolean?
)

data class PipedCommentsResponse(
    val comments: List<PipedComment>,
    val nextpage: String?
)

data class PipedComment(
    val commentId: String?,
    val author: String?,
    val thumbnail: String?,
    val commentText: String?,
    val likeCount: Int?,
    val publishedText: String?,
    val replyCount: Int?,
    val hearted: Boolean?,
    val pinned: Boolean?
)

data class PipedChannelResponse(
    val name: String?,
    val avatarUrl: String?,
    val bannerUrl: String?,
    val description: String?,
    val subscribers: Long?,
    val verified: Boolean?,
    val relatedStreams: List<PipedVideoResponse>?,
    val nextpage: String?
)

data class PipedPlaylistResponse(
    val name: String?,
    val description: String?,
    val thumbnailUrl: String?,
    val uploader: String?,
    val uploaderUrl: String?,
    val videos: Int?,
    val relatedStreams: List<PipedVideoResponse>?,
    val nextpage: String?
)
