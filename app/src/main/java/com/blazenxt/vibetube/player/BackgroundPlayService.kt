package com.blazenxt.vibetube.player

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.blazenxt.vibetube.R
import com.blazenxt.vibetube.VibeTubeApp
import com.blazenxt.vibetube.ui.MainActivity
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

class BackgroundPlayService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var currentTitle: String = ""
    private var currentChannel: String = ""

    override fun onCreate() {
        super.onCreate()
        
        val player = Player.Builder(this).build()
        
        mediaSession = MediaSession.Builder(this, player)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = mediaSession?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
        }
        super.onDestroy()
    }

    fun updateMetadata(title: String, channel: String) {
        currentTitle = title
        currentChannel = channel
    }

    companion object {
        private const val NOTIFICATION_ID = 1001
        const val ACTION_PLAY = "com.blazenxt.vibetube.ACTION_PLAY"
        const val ACTION_PAUSE = "com.blazenxt.vibetube.ACTION_PAUSE"
        const val ACTION_NEXT = "com.blazenxt.vibetube.ACTION_NEXT"
        const val ACTION_PREVIOUS = "com.blazenxt.vibetube.ACTION_PREVIOUS"
        const val ACTION_STOP = "com.blazenxt.vibetube.ACTION_STOP"
    }
}
