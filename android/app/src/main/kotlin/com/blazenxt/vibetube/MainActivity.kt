package com.blazenxt.vibetube

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.blazenxt.vibetube/player"
    private val deepLinkChannelName = "com.blazenxt.vibetube/deeplink"
    private var methodChannel: MethodChannel? = null
    private var deepLinkChannel: MethodChannel? = null
    private var autoPip = true
    /** Only enter PiP / auto-PiP when Flutter reports active playback. */
    private var isPlaying = false

    /**
     * A deep link that arrived before the Dart side registered its handler
     * (cold start). Delivered as soon as Flutter asks for it.
     */
    private var pendingDeepLink: String? = null
    private var deepLinkReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkChannelName)
        PlaybackService.flutterChannel = methodChannel

        // Dart calls this once its handler is installed; until then any
        // incoming link is buffered in pendingDeepLink.
        deepLinkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    deepLinkReady = true
                    pendingDeepLink?.let { id ->
                        pendingDeepLink = null
                        deepLinkChannel?.invokeMethod("onDeepLink", id)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Handle deep links (YouTube URLs opened from other apps)
        handleDeepLink(intent)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    val ok = if (isPlaying) enterPipMode() else false
                    result.success(ok)
                }
                "setAutoPip" -> {
                    autoPip = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "setPlaying" -> {
                    isPlaying = call.argument<Boolean>("playing") ?: false
                    // Keep MediaSession in sync
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_PLAYING_STATE
                        putExtra("playing", isPlaying)
                    }
                    try {
                        startService(intent)
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                "startBackground" -> {
                    val title = call.argument<String>("title") ?: "VibeTube"
                    val artist = call.argument<String>("artist") ?: "Playing"
                    val playing = call.argument<Boolean>("playing") ?: true
                    isPlaying = playing
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_START
                        putExtra("title", title)
                        putExtra("artist", artist)
                        putExtra("playing", playing)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "updateBackground" -> {
                    val title = call.argument<String>("title") ?: "VibeTube"
                    val artist = call.argument<String>("artist") ?: "Playing"
                    val playing = call.argument<Boolean>("playing") ?: isPlaying
                    isPlaying = playing
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_UPDATE
                        putExtra("title", title)
                        putExtra("artist", artist)
                        putExtra("playing", playing)
                    }
                    try {
                        startService(intent)
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "stopBackground" -> {
                    isPlaying = false
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_STOP
                    }
                    try {
                        startService(intent)
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "isPipSupported" -> {
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(
                                android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
                            )
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!isPlaying) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val data = intent?.data ?: return
        val videoId = extractVideoId(data) ?: return
        // Consume the URI so a config change / re-create doesn't replay it.
        intent.data = null
        if (deepLinkReady) {
            try {
                deepLinkChannel?.invokeMethod("onDeepLink", videoId)
            } catch (_: Exception) {
                pendingDeepLink = videoId
            }
        } else {
            // Engine not listening yet — deliver on "ready" instead of racing
            // a fixed timeout.
            pendingDeepLink = videoId
        }
    }

    private fun extractVideoId(uri: android.net.Uri): String? {
        val host = uri.host?.lowercase() ?: return null
        // youtu.be/VIDEO_ID
        if (host == "youtu.be") {
            val id = uri.pathSegments.firstOrNull()
            if (id != null && id.length == 11) return id
        }
        // youtube.com/watch?v=VIDEO_ID or /shorts/VIDEO_ID
        if (host.contains("youtube.com")) {
            val v = uri.getQueryParameter("v")
            if (v != null && v.length == 11) return v
            val path = uri.pathSegments
            if (path.size >= 2 && path[0] == "shorts") {
                val id = path[1]
                if (id.length == 11) return id
            }
            if (path.size >= 2 && path[0] == "embed") {
                val id = path[1]
                if (id.length == 11) return id
            }
        }
        return null
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Auto-PiP ONLY while a video is actively playing
        if (autoPip && isPlaying && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPipMode()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        }
        methodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
