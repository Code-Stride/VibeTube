package com.blazenxt.vibetube

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** Must match ShareLinks.host and the App Links intent-filter. */
        const val LINK_HOST = "code-stride.github.io"
        const val APP_SCHEME = "vibetube"

        /** Broadcast the PiP action buttons send back to us. */
        private const val ACTION_PIP_CONTROL = "com.blazenxt.vibetube.PIP_CONTROL"
        private const val EXTRA_CONTROL = "control"
        private const val CONTROL_PLAY = 1
        private const val CONTROL_PAUSE = 2
        private const val CONTROL_REWIND = 3
        private const val CONTROL_FORWARD = 4
    }

    /**
     * Start [PlaybackService] the way Android 8+ requires.
     *
     * Three of the four call sites used plain startService(), which throws
     * IllegalStateException from the background — and the throw was swallowed
     * by an empty catch, so play/pause state silently stopped reaching the
     * MediaSession and the notification desynced from playback with nothing in
     * the log to show for it.
     *
     * Every branch of PlaybackService.onStartCommand calls ensureForeground(),
     * so the 5-second startForeground() contract is satisfied.
     */
    private fun sendToPlaybackService(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.w("VibeTube", "PlaybackService start failed (${intent.action}): ${e.message}")
        }
    }

    /** Video aspect ratio reported by Flutter, so PiP isn't always 16:9. */
    private var videoAspect: Rational = Rational(16, 9)
    private var pipReceiver: BroadcastReceiver? = null

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

        registerPipReceiver()

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
                    updatePipParams()
                    result.success(null)
                }
                "setPlaying" -> {
                    isPlaying = call.argument<Boolean>("playing") ?: false
                    // Keep the PiP play/pause button and auto-enter flag in
                    // step with reality.
                    updatePipParams()
                    // Keep MediaSession in sync
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_PLAYING_STATE
                        putExtra("playing", isPlaying)
                    }
                    sendToPlaybackService(intent)
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
                    sendToPlaybackService(intent)
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
                    sendToPlaybackService(intent)
                    result.success(true)
                }
                "stopBackground" -> {
                    isPlaying = false
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_STOP
                    }
                    sendToPlaybackService(intent)
                    result.success(true)
                }
                "setVideoAspect" -> {
                    val w = call.argument<Int>("width") ?: 16
                    val h = call.argument<Int>("height") ?: 9
                    // Android rejects extreme ratios; clamp to the documented
                    // range so a Short (9:16) doesn't throw.
                    if (w > 0 && h > 0) {
                        val r = w.toFloat() / h.toFloat()
                        videoAspect = when {
                            r < 0.42f -> Rational(42, 100)
                            r > 2.39f -> Rational(239, 100)
                            else -> Rational(w, h)
                        }
                        updatePipParams()
                    }
                    result.success(null)
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

    /**
     * Builds the PiP window's transport controls. Without these the window is
     * just a video with no way to pause it, which is the main thing that made
     * our PiP feel unfinished next to YouTube's.
     */
    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        fun action(control: Int, icon: Int, title: String): RemoteAction {
            val pi = PendingIntent.getBroadcast(
                this,
                control,
                Intent(ACTION_PIP_CONTROL)
                    .putExtra(EXTRA_CONTROL, control)
                    .setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            return RemoteAction(Icon.createWithResource(this, icon), title, title, pi)
        }
        return listOf(
            action(CONTROL_REWIND, android.R.drawable.ic_media_rew, "Rewind"),
            if (isPlaying) {
                action(CONTROL_PAUSE, android.R.drawable.ic_media_pause, "Pause")
            } else {
                action(CONTROL_PLAY, android.R.drawable.ic_media_play, "Play")
            },
            action(CONTROL_FORWARD, android.R.drawable.ic_media_ff, "Forward")
        )
    }

    private fun pipParams(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder()
            .setAspectRatio(videoAspect)
            .setActions(buildPipActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Seamless resize for video, and let Android put us into PiP on
            // its own during the gesture — this is what makes YouTube's
            // transition smooth instead of a visible jump on home-swipe.
            b.setSeamlessResizeEnabled(true)
            b.setAutoEnterEnabled(autoPip && isPlaying)
        }
        return b.build()
    }

    /** Refresh the PiP buttons so play/pause reflects the real state. */
    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            setPictureInPictureParams(pipParams())
        } catch (_: Exception) {
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!isPlaying) return false
        return try {
            enterPictureInPictureMode(pipParams())
        } catch (e: Exception) {
            false
        }
    }

    private fun registerPipReceiver() {
        if (pipReceiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.getIntExtra(EXTRA_CONTROL, -1)) {
                    CONTROL_PLAY -> methodChannel?.invokeMethod("mediaPlay", null)
                    CONTROL_PAUSE -> methodChannel?.invokeMethod("mediaPause", null)
                    CONTROL_REWIND -> methodChannel?.invokeMethod("mediaRewind", null)
                    CONTROL_FORWARD -> methodChannel?.invokeMethod("mediaForward", null)
                }
            }
        }
        val filter = IntentFilter(ACTION_PIP_CONTROL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(r, filter)
        }
        pipReceiver = r
    }

    /**
     * Release the engine-scoped references.
     *
     * PlaybackService.flutterChannel is static and nothing ever cleared it:
     * MethodChannel -> BinaryMessenger -> DartExecutor retained the whole
     * FlutterEngine, and this Activity with it, across every recreate. The
     * second-order effect was worse than the leak — once the Activity was gone
     * but the service was not, notifyFlutter() pushed media-button callbacks
     * into a dead messenger where an empty catch swallowed them, so the
     * notification's Play button quietly stopped working.
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (PlaybackService.flutterChannel === methodChannel) {
            PlaybackService.flutterChannel = null
        }
        methodChannel?.setMethodCallHandler(null)
        deepLinkChannel?.setMethodCallHandler(null)
        methodChannel = null
        deepLinkChannel = null
        deepLinkReady = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        pipReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        pipReceiver = null
        super.onDestroy()
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

    private val idPattern = Regex("^[A-Za-z0-9_-]{11}$")

    private fun validId(id: String?): String? =
        id?.trim()?.takeIf { idPattern.matches(it) }

    private fun extractVideoId(uri: android.net.Uri): String? {
        // vibetube://watch?v=ID (also tolerate vibetube://ID)
        if (uri.scheme.equals(APP_SCHEME, ignoreCase = true)) {
            return validId(uri.getQueryParameter("v"))
                ?: validId(uri.host)
                ?: validId(uri.pathSegments?.lastOrNull())
        }

        val host = uri.host?.lowercase() ?: return null
        val path = uri.pathSegments?.filter { it.isNotEmpty() } ?: emptyList()

        // Our own share link: https://<LINK_HOST>/VibeTube/w/ID
        if (host == LINK_HOST) {
            val i = path.indexOf("w")
            if (i != -1 && i + 1 < path.size) return validId(path[i + 1])
            return validId(uri.getQueryParameter("v"))
        }

        // youtu.be/VIDEO_ID
        if (host == "youtu.be") {
            return validId(path.firstOrNull())
        }

        // youtube.com/watch?v=ID, /shorts/ID, /embed/ID, /live/ID
        if (host.endsWith("youtube.com")) {
            validId(uri.getQueryParameter("v"))?.let { return it }
            if (path.size >= 2 && path[0] in setOf("shorts", "embed", "live", "v")) {
                return validId(path[1])
            }
        }
        return null
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // On Android 12+ setAutoEnterEnabled already handles this, and calling
        // enterPictureInPictureMode as well produces a visible double
        // transition. Only drive it manually on 8..11.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
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
        if (isInPictureInPictureMode) updatePipParams()
    }
}
