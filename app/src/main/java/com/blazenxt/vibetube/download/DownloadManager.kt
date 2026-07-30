package com.blazenxt.vibetube.download

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import androidx.room.*
import kotlinx.coroutines.flow.Flow
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Entity(tableName = "downloads")
data class DownloadEntity(
    @PrimaryKey
    val id: String,
    val videoId: String,
    val title: String,
    val thumbnailUrl: String,
    val channelName: String,
    val quality: String,
    val format: String,
    val fileSize: Long = 0,
    val downloadedSize: Long = 0,
    val filePath: String = "",
    val status: DownloadStatus = DownloadStatus.PENDING,
    val progress: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val completedAt: Long? = null
)

enum class DownloadStatus {
    PENDING, DOWNLOADING, PAUSED, COMPLETED, FAILED, CANCELLED
}

@Dao
interface DownloadDao {
    @Query("SELECT * FROM downloads ORDER BY createdAt DESC")
    fun getAllDownloads(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE status = :status")
    fun getDownloadsByStatus(status: DownloadStatus): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE videoId = :videoId")
    suspend fun getDownloadByVideoId(videoId: String): DownloadEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDownload(download: DownloadEntity)

    @Update
    suspend fun updateDownload(download: DownloadEntity)

    @Delete
    suspend fun deleteDownload(download: DownloadEntity)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun deleteDownloadById(id: String)

    @Query("UPDATE downloads SET status = :status, progress = :progress, downloadedSize = :downloadedSize WHERE id = :id")
    suspend fun updateDownloadProgress(id: String, status: DownloadStatus, progress: Int, downloadedSize: Long)
}

@Database(entities = [DownloadEntity::class], version = 1, exportSchema = false)
abstract class DownloadDatabase : RoomDatabase() {
    abstract fun downloadDao(): DownloadDao
}

@Singleton
class DownloadManager @Inject constructor(
    private val context: Context,
    private val downloadDao: DownloadDao
) {
    private val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val activeDownloads = mutableMapOf<String, Long>() // downloadId -> androidDownloadId

    fun getAllDownloads(): Flow<List<DownloadEntity>> = downloadDao.getAllDownloads()

    suspend fun startDownload(
        videoId: String,
        title: String,
        thumbnailUrl: String,
        channelName: String,
        streamUrl: String,
        quality: String,
        format: String
    ): String {
        val downloadId = "download_${videoId}_${System.currentTimeMillis()}"
        
        val fileName = sanitizeFileName("${title}_${quality}")
        val extension = if (format.contains("audio")) "mp3" else "mp4"
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "VibeTube"
        )
        directory.mkdirs()

        val downloadEntity = DownloadEntity(
            id = downloadId,
            videoId = videoId,
            title = title,
            thumbnailUrl = thumbnailUrl,
            channelName = channelName,
            quality = quality,
            format = format,
            filePath = File(directory, "$fileName.$extension").absolutePath,
            status = DownloadStatus.PENDING
        )
        
        downloadDao.insertDownload(downloadEntity)

        try {
            val request = DownloadManager.Request(Uri.parse(streamUrl))
                .setTitle(title)
                .setDescription("Downloading $quality")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationUri(Uri.fromFile(File(directory, "$fileName.$extension")))
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)

            val androidDownloadId = downloadManager.enqueue(request)
            activeDownloads[downloadId] = androidDownloadId

            downloadDao.updateDownloadProgress(
                downloadId,
                DownloadStatus.DOWNLOADING,
                0,
                0
            )

            Timber.d("Started download: $downloadId for $title")
            return downloadId
        } catch (e: Exception) {
            Timber.e(e, "Failed to start download")
            downloadDao.updateDownloadProgress(
                downloadId,
                DownloadStatus.FAILED,
                0,
                0
            )
            throw e
        }
    }

    suspend fun pauseDownload(downloadId: String) {
        activeDownloads[downloadId]?.let { androidDownloadId ->
            downloadManager.remove(androidDownloadId)
            downloadDao.updateDownloadProgress(
                downloadId,
                DownloadStatus.PAUSED,
                0,
                0
            )
        }
    }

    suspend fun resumeDownload(downloadId: String, streamUrl: String) {
        downloadDao.getDownloadByVideoId(downloadId)?.let { download ->
            // Re-enqueue the download
            startDownload(
                download.videoId,
                download.title,
                download.thumbnailUrl,
                download.channelName,
                streamUrl,
                download.quality,
                download.format
            )
        }
    }

    suspend fun cancelDownload(downloadId: String) {
        activeDownloads[downloadId]?.let { androidDownloadId ->
            downloadManager.remove(androidDownloadId)
            activeDownloads.remove(downloadId)
        }
        downloadDao.updateDownloadProgress(
            downloadId,
            DownloadStatus.CANCELLED,
            0,
            0
        )
    }

    suspend fun deleteDownload(downloadId: String) {
        downloadDao.getDownloadByVideoId(downloadId)?.let { download ->
            File(download.filePath).delete()
        }
        downloadDao.deleteDownloadById(downloadId)
    }

    suspend fun onDownloadComplete(downloadId: String) {
        downloadDao.updateDownloadProgress(
            downloadId,
            DownloadStatus.COMPLETED,
            100,
            0
        )
        activeDownloads.remove(downloadId)
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .take(100)
    }

    fun getDownloadDirectory(): File {
        return File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "VibeTube"
        ).also { it.mkdirs() }
    }
}
