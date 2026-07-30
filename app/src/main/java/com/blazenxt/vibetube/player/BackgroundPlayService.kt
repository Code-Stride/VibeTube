package com.blazenxt.vibetube.player

import android.content.Intent
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class BackgroundPlayService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var currentTitle: String = ""
    private var currentChannel: String = ""

    override fun onCreate() {
        super.onCreate()
        
        val player = ExoPlayer.Builder(this).build()
        
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
