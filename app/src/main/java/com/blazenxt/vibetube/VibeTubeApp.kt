package com.blazenxt.vibetube

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class VibeTubeApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override fun onCreate() {
        super.onCreate()
        
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
        
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            val mediaChannel = NotificationChannel(
                CHANNEL_MEDIA_PLAYBACK,
                "Background Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows controls for background video/audio playback"
                setShowBadge(false)
            }

            val downloadChannel = NotificationChannel(
                CHANNEL_DOWNLOADS,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows download progress"
                setShowBadge(true)
            }

            val downloadCompleteChannel = NotificationChannel(
                CHANNEL_DOWNLOAD_COMPLETE,
                "Download Complete",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifies when download is complete"
                setShowBadge(true)
            }

            notificationManager.createNotificationChannels(
                listOf(mediaChannel, downloadChannel, downloadCompleteChannel)
            )
        }
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    companion object {
        const val CHANNEL_MEDIA_PLAYBACK = "media_playback"
        const val CHANNEL_DOWNLOADS = "downloads"
        const val CHANNEL_DOWNLOAD_COMPLETE = "download_complete"
    }
}
