package com.blazenxt.vibetube.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.io.Serializable

@Entity(tableName = "videos")
data class Video(
    @PrimaryKey
    val id: String,
    val title: String,
    val description: String = "",
    val thumbnailUrl: String = "",
    val channelName: String = "",
    val channelId: String = "",
    val channelAvatar: String = "",
    val viewCount: Long = 0,
    val likeCount: Long = 0,
    val duration: Long = 0, // in seconds
    val publishedAt: String = "",
    val url: String = "",
    val isLive: Boolean = false
) : Serializable {

    fun getFormattedViewCount(): String {
        return when {
            viewCount >= 1_000_000_000 -> String.format("%.1fB", viewCount / 1_000_000_000.0)
            viewCount >= 1_000_000 -> String.format("%.1fM", viewCount / 1_000_000.0)
            viewCount >= 1_000 -> String.format("%.1fK", viewCount / 1_000.0)
            else -> viewCount.toString()
        }
    }

    fun getFormattedDuration(): String {
        if (isLive) return "LIVE"
        val hours = duration / 3600
        val minutes = (duration % 3600) / 60
        val seconds = duration % 60
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    fun getFormattedPublishedDate(): String {
        // Simplified - returns relative time
        return publishedAt
    }
}

data class VideoStream(
    val url: String,
    val quality: String,
    val format: String,
    val width: Int = 0,
    val height: Int = 0,
    val fps: Int = 30,
    val bitrate: Long = 0,
    val isVideoOnly: Boolean = false,
    val isAudioOnly: Boolean = false
) {
    fun getQualityLabel(): String {
        return when {
            isAudioOnly -> "Audio Only"
            isVideoOnly -> "$quality (Video Only)"
            else -> quality
        }
    }
}

data class SearchResult(
    val videos: List<Video>,
    val nextPageToken: String? = null
)

data class Comment(
    val id: String,
    val author: String,
    val authorAvatar: String,
    val text: String,
    val likeCount: Int = 0,
    val publishedAt: String = "",
    val replyCount: Int = 0,
    val isHearted: Boolean = false
)

data class Playlist(
    val id: String,
    val title: String,
    val description: String = "",
    val thumbnailUrl: String = "",
    val channelName: String = "",
    val videoCount: Int = 0,
    val videos: List<Video> = emptyList()
)
