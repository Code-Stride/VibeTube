package com.blazenxt.vibetube.player

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
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
    private var currentThumbnail: Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        
        val player = Player.Builder(this).build()
        
        mediaSession = MediaSession.Builder(this, player)
            .setCallback(SessionCallback())
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

    private inner class SessionCallback : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {
            when (customCommand.customAction) {
                ACTION_SET_METADATA -> {
                    currentTitle = args.getString("title", "")
                    currentChannel = args.getString("channel", "")
                    updateNotification()
                }
                ACTION_SET_THUMBNAIL -> {
                    // Handle thumbnail setting
                }
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        override fun onPlayerCommandFinished(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            playerCommand: Int
        ) {
            super.onPlayerCommandFinished(session, controller, playerCommand)
            updateNotification()
        }
    }

    private fun updateNotification() {
        val player = mediaSession?.player ?: return
        
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, VibeTubeApp.CHANNEL_MEDIA_PLAYBACK)
            .setContentTitle(currentTitle)
            .setContentText(currentChannel)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(currentThumbnail)
            .setContentIntent(pendingIntent)
            .setOngoing(player.isPlaying)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .apply {
                // Add media controls
                if (player.isPlaying) {
                    addAction(R.drawable.ic_pause, "Pause", 
                        getActionIntent(ACTION_PAUSE))
                } else {
                    addAction(R.drawable.ic_play_arrow, "Play",
                        getActionIntent(ACTION_PLAY))
                }
                addAction(R.drawable.ic_skip_next, "Next",
                    getActionIntent(ACTION_NEXT))
                addAction(R.drawable.ic_stop, "Stop",
                    getActionIntent(ACTION_STOP))
            }
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession?.sessionCompatToken)
                    .setShowActionsInCompactView(0, 1)
            )
            .build()

        if (player.isPlaying || player.playWhenReady) {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun getActionIntent(action: String): PendingIntent {
        val intent = Intent(this, MediaButtonReceiver::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            this, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        private const val NOTIFICATION_ID = 1001
        const val ACTION_PLAY = "com.blazenxt.vibetube.ACTION_PLAY"
        const val ACTION_PAUSE = "com.blazenxt.vibetube.ACTION_PAUSE"
        const val ACTION_NEXT = "com.blazenxt.vibetube.ACTION_NEXT"
        const val ACTION_PREVIOUS = "com.blazenxt.vibetube.ACTION_PREVIOUS"
        const val ACTION_STOP = "com.blazenxt.vibetube.ACTION_STOP"
        const val ACTION_SET_METADATA = "com.blazenxt.vibetube.SET_METADATA"
        const val ACTION_SET_THUMBNAIL = "com.blazenxt.vibetube.SET_THUMBNAIL"
    }
}
