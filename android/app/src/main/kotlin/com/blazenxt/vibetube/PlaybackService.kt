package com.blazenxt.vibetube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class PlaybackService : Service() {
    companion object {
        const val ACTION_START = "vibetube.START"
        const val ACTION_STOP = "vibetube.STOP"
        const val CHANNEL_ID = "vibetube_playback"
        const val NOTIF_ID = 4401
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val title = intent?.getStringExtra("title") ?: "VibeTube"
                val artist = intent?.getStringExtra("artist") ?: "Playing in background"
                startForeground(NOTIF_ID, buildNotification(title, artist))
            }
        }
        return START_STICKY
    }

    private fun buildNotification(title: String, artist: String): Notification {
        createChannel()
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val pi = PendingIntent.getActivity(this, 0, launch, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Playback",
                NotificationManager.IMPORTANCE_LOW
            )
            ch.description = "Background playback"
            ch.setShowBadge(false)
            mgr?.createNotificationChannel(ch)
        }
    }
}
