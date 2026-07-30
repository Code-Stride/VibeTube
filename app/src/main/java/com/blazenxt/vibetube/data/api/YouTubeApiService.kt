package com.blazenxt.vibetube.data.api

import com.blazenxt.vibetube.data.model.Video
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

interface YouTubeApiService {

    @GET("videos")
    suspend fun getPopularVideos(
        @Query("part") part: String = "snippet,statistics",
        @Query("chart") chart: String = "mostPopular",
        @Query("maxResults") maxResults: Int = 50,
        @Query("regionCode") regionCode: String = "US"
    ): YouTubeVideoResponse

    @GET("search")
    suspend fun searchVideos(
        @Query("part") part: String = "snippet",
        @Query("q") query: String,
        @Query("type") type: String = "video",
        @Query("maxResults") maxResults: Int = 50,
        @Query("pageToken") pageToken: String? = null
    ): YouTubeSearchResponse

    @GET("videos")
    suspend fun getVideoDetails(
        @Query("part") part: String = "snippet,statistics,contentDetails",
        @Query("id") videoId: String
    ): YouTubeVideoResponse

    @GET("commentThreads")
    suspend fun getComments(
        @Query("part") part: String = "snippet",
        @Query("videoId") videoId: String,
        @Query("maxResults") maxResults: Int = 100,
        @Query("pageToken") pageToken: String? = null,
        @Query("order") order: String = "relevance"
    ): YouTubeCommentResponse

    @GET("channels")
    suspend fun getChannelDetails(
        @Query("part") part: String = "snippet,statistics",
        @Query("id") channelId: String
    ): YouTubeChannelResponse

    @GET("playlists")
    suspend fun getPlaylist(
        @Query("part") part: String = "snippet,contentDetails",
        @Query("id") playlistId: String
    ): YouTubePlaylistResponse

    @GET("playlistItems")
    suspend fun getPlaylistItems(
        @Query("part") part: String = "snippet",
        @Query("playlistId") playlistId: String,
        @Query("maxResults") maxResults: Int = 50,
        @Query("pageToken") pageToken: String? = null
    ): YouTubePlaylistItemResponse
}

// YouTube API Response Models
data class YouTubeVideoResponse(
    val items: List<YouTubeVideoItem> = emptyList(),
    val nextPageToken: String? = null,
    val pageInfo: YouTubePageInfo? = null
)

data class YouTubeVideoItem(
    val id: String = "",
    val snippet: YouTubeSnippet? = null,
    val statistics: YouTubeStatistics? = null,
    val contentDetails: YouTubeContentDetails? = null
)

data class YouTubeSnippet(
    val title: String = "",
    val description: String = "",
    val channelTitle: String = "",
    val channelId: String = "",
    val publishedAt: String = "",
    val thumbnails: YouTubeThumbnails? = null
)

data class YouTubeThumbnails(
    val default: YouTubeThumbnail? = null,
    val medium: YouTubeThumbnail? = null,
    val high: YouTubeThumbnail? = null,
    val standard: YouTubeThumbnail? = null,
    val maxres: YouTubeThumbnail? = null
)

data class YouTubeThumbnail(
    val url: String = "",
    val width: Int = 0,
    val height: Int = 0
)

data class YouTubeStatistics(
    val viewCount: String = "0",
    val likeCount: String = "0",
    val dislikeCount: String = "0",
    val favoriteCount: String = "0",
    val commentCount: String = "0"
)

data class YouTubeContentDetails(
    val duration: String = "",
    val dimension: String = "",
    val definition: String = ""
)

data class YouTubePageInfo(
    val totalResults: Int = 0,
    val resultsPerPage: Int = 0
)

data class YouTubeSearchResponse(
    val items: List<YouTubeSearchItem> = emptyList(),
    val nextPageToken: String? = null,
    val pageInfo: YouTubePageInfo? = null
)

data class YouTubeSearchItem(
    val id: YouTubeVideoId? = null,
    val snippet: YouTubeSnippet? = null
)

data class YouTubeVideoId(
    val videoId: String = ""
)

data class YouTubeCommentResponse(
    val items: List<YouTubeCommentItem> = emptyList(),
    val nextPageToken: String? = null
)

data class YouTubeCommentItem(
    val id: String = "",
    val snippet: YouTubeCommentSnippet? = null
)

data class YouTubeCommentSnippet(
    val topLevelComment: YouTubeTopLevelComment? = null,
    val totalReplyCount: Int = 0
)

data class YouTubeTopLevelComment(
    val id: String = "",
    val snippet: YouTubeCommentText? = null
)

data class YouTubeCommentText(
    val authorDisplayName: String = "",
    val authorProfileImageUrl: String = "",
    val textDisplay: String = "",
    val likeCount: Int = 0,
    val publishedAt: String = ""
)

data class YouTubeChannelResponse(
    val items: List<YouTubeChannelItem> = emptyList()
)

data class YouTubeChannelItem(
    val id: String = "",
    val snippet: YouTubeSnippet? = null,
    val statistics: YouTubeChannelStatistics? = null
)

data class YouTubeChannelStatistics(
    val viewCount: String = "0",
    val subscriberCount: String = "0",
    val hiddenSubscriberCount: Boolean = false,
    val videoCount: String = "0"
)

data class YouTubePlaylistResponse(
    val items: List<YouTubePlaylistItem> = emptyList()
)

data class YouTubePlaylistItem(
    val id: String = "",
    val snippet: YouTubeSnippet? = null,
    val contentDetails: YouTubePlaylistContentDetails? = null
)

data class YouTubePlaylistContentDetails(
    val itemCount: Int = 0
)

data class YouTubePlaylistItemResponse(
    val items: List<YouTubePlaylistItemEntry> = emptyList(),
    val nextPageToken: String? = null
)

data class YouTubePlaylistItemEntry(
    val id: String = "",
    val snippet: YouTubePlaylistItemSnippet? = null
)

data class YouTubePlaylistItemSnippet(
    val title: String = "",
    val description: String = "",
    val channelTitle: String = "",
    val publishedAt: String = "",
    val resourceId: YouTubeResourceId? = null,
    val thumbnails: YouTubeThumbnails? = null
)

data class YouTubeResourceId(
    val videoId: String = ""
)
