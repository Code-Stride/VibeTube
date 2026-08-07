package com.blazenxt.vibetube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground media service with MediaSession so the phone system
 * (lock screen, Bluetooth, notification shade, Android Auto-ish) detects playback.
 */
class PlaybackService : Service() {
    companion object {
        const val ACTION_START = "vibetube.START"
        const val ACTION_STOP = "vibetube.STOP"
        const val ACTION_UPDATE = "vibetube.UPDATE"
        const val ACTION_PLAYING_STATE = "vibetube.PLAYING_STATE"
        const val ACTION_PLAY = "vibetube.PLAY"
        const val ACTION_PAUSE = "vibetube.PAUSE"
        const val ACTION_TOGGLE = "vibetube.TOGGLE"
        const val CHANNEL_ID = "vibetube_playback"
        const val NOTIF_ID = 4401

        @JvmField
        var flutterChannel: MethodChannel? = null
    }

    private var mediaSession: MediaSession? = null
    private var title: String = "VibeTube"
    private var artist: String = "Playing"
    private var playing: Boolean = true

    /**
     * Whether startForeground() has already run for this service instance.
     * On Android 8+ a service started with startForegroundService() MUST call
     * startForeground() within ~5s or the system throws
     * ForegroundServiceDidNotStartInTimeException and kills the app.
     */
    private var isForeground = false

    /** Promote to foreground exactly once; later calls just refresh. */
    private fun ensureForeground() {
        if (isForeground) {
            refreshNotification()
            return
        }
        try {
            startForeground(NOTIF_ID, buildNotification())
            isForeground = true
        } catch (_: Exception) {
            // e.g. missing POST_NOTIFICATIONS on API 33+ — degrade gracefully
            // instead of taking the whole app down.
        }
    }

    override fun onCreate() {
        super.onCreate()
        mediaSession = MediaSession(this, "VibeTubeSession").apply {
            @Suppress("DEPRECATION")
            setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    playing = true
                    pushState()
                    notifyFlutter("mediaPlay")
                    refreshNotification()
                }

                override fun onPause() {
                    playing = false
                    pushState()
                    notifyFlutter("mediaPause")
                    refreshNotification()
                }

                override fun onStop() {
                    playing = false
                    pushState()
                    notifyFlutter("mediaStop")
                    stopSelfSafe()
                }
            })
            isActive = true
        }
        pushState()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfSafe()
                return START_NOT_STICKY
            }
            ACTION_PLAY -> {
                playing = true
                pushState()
                notifyFlutter("mediaPlay")
                ensureForeground()
            }
            ACTION_PAUSE -> {
                playing = false
                pushState()
                notifyFlutter("mediaPause")
                ensureForeground()
            }
            ACTION_TOGGLE -> {
                playing = !playing
                pushState()
                notifyFlutter(if (playing) "mediaPlay" else "mediaPause")
                ensureForeground()
            }
            ACTION_PLAYING_STATE -> {
                playing = intent.getBooleanExtra("playing", playing)
                pushState()
                ensureForeground()
            }
            ACTION_UPDATE, ACTION_START, null -> {
                title = intent?.getStringExtra("title") ?: title
                artist = intent?.getStringExtra("artist") ?: artist
                if (intent?.hasExtra("playing") == true) {
                    playing = intent.getBooleanExtra("playing", true)
                }
                mediaSession?.setMetadata(
                    MediaMetadata.Builder()
                        .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                        .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                        .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, title)
                        .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, artist)
                        .build()
                )
                pushState()
                ensureForeground()
            }
        }
        // Use START_NOT_STICKY to avoid restarting with null/stale intent after system kill
        return START_NOT_STICKY
    }

    private fun pushState() {
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP
        val state = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        mediaSession?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (playing) 1f else 0f)
                .build()
        )
    }

    private fun refreshNotification() {
        val mgr = getSystemService(NotificationManager::class.java)
        mgr?.notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        createChannel()
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val contentPi = PendingIntent.getActivity(this, 0, launch, piFlags)

        val playPauseAction = if (playing) ACTION_PAUSE else ACTION_PLAY
        val playPauseIcon =
            if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (playing) "Pause" else "Play"
        val playPausePi = PendingIntent.getService(
            this, 1,
            Intent(this, PlaybackService::class.java).setAction(playPauseAction),
            piFlags
        )
        val stopPi = PendingIntent.getService(
            this, 2,
            Intent(this, PlaybackService::class.java).setAction(ACTION_STOP),
            piFlags
        )
        // setOngoing(false) while paused makes the notification swipeable.
        // Without a delete intent the swipe only removed the notification and
        // left the service running with a live MediaSession — a zombie holding
        // audio focus that the user had no remaining control surface for.
        val deletePi = PendingIntent.getService(
            this, 3,
            Intent(this, PlaybackService::class.java).setAction(ACTION_STOP),
            piFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentPi)
            .setDeleteIntent(deletePi)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(playPauseIcon, playPauseLabel, playPausePi).build())
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPi
                ).build()
            )

        val session = mediaSession
        if (session != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.style = Notification.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1)
        }

        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Media playback",
                NotificationManager.IMPORTANCE_LOW
            )
            ch.description = "VibeTube background & lock-screen controls"
            ch.setShowBadge(false)
            ch.setSound(null, null)
            mgr?.createNotificationChannel(ch)
        }
    }

    private fun notifyFlutter(method: String) {
        try {
            flutterChannel?.invokeMethod(method, null)
        } catch (_: Exception) {
        }
    }

    private fun stopSelfSafe() {
        try {
            mediaSession?.isActive = false
        } catch (_: Exception) {
        }
        // If we were launched via startForegroundService() but stopped before
        // ever promoting, we still owe the system a startForeground() call.
        if (!isForeground) {
            try {
                startForeground(NOTIF_ID, buildNotification())
                isForeground = true
            } catch (_: Exception) {
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        isForeground = false
        stopSelf()
    }

    override fun onDestroy() {
        try {
            mediaSession?.release()
        } catch (_: Exception) {
        }
        mediaSession = null
        super.onDestroy()
    }
}
