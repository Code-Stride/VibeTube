package com.blazenxt.vibetube

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.blazenxt.vibetube/player"
    private var methodChannel: MethodChannel? = null
    private var autoPip = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    val ok = enterPipMode()
                    result.success(ok)
                }
                "setAutoPip" -> {
                    autoPip = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "startBackground" -> {
                    val title = call.argument<String>("title") ?: "VibeTube"
                    val artist = call.argument<String>("artist") ?: "Playing"
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_START
                        putExtra("title", title)
                        putExtra("artist", artist)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopBackground" -> {
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        action = PlaybackService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "isPipSupported" -> {
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
