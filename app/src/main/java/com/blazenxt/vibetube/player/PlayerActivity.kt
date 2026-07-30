package com.blazenxt.vibetube.player

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.blazenxt.vibetube.R
import com.blazenxt.vibetube.sponsorblock.SponsorSegment
import com.google.android.material.bottomsheet.BottomSheetDialog
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.*

@AndroidEntryPoint
class PlayerActivity : AppCompatActivity() {

    private lateinit var playerView: PlayerView
    private var exoPlayer: ExoPlayer? = null
    private var sponsorSegments: List<SponsorSegment> = emptyList()
    private var sponsorSkipJob: Job? = null
    
    private var videoId: String = ""
    private var videoTitle: String = ""
    private var isBackgroundPlayEnabled = true
    private var isSponsorBlockEnabled = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)

        hideSystemUI()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        playerView = findViewById(R.id.player_view)
        
        videoId = intent.getStringExtra("video_id") ?: ""
        videoTitle = intent.getStringExtra("video_title") ?: ""

        setupPlayer()
        setupControls()
    }

    private fun hideSystemUI() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, playerView).let { controller ->
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun setupPlayer() {
        exoPlayer = ExoPlayer.Builder(this)
            .build()
            .also { player ->
                playerView.player = player
                playerView.keepScreenOn = true
                
                // Enable background play
                player.playWhenReady = true
                
                loadVideo(videoId)
                
                player.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(playbackState: Int) {
                        when (playbackState) {
                            Player.STATE_READY -> startSponsorSkipMonitor()
                            Player.STATE_ENDED -> finish()
                        }
                    }

                    override fun onPlayerError(error: PlaybackException) {
                        // Handle error
                    }
                })
            }
    }

    private fun loadVideo(videoId: String) {
        // Load using Piped API streams
        val videoUrl = "https://pipedapi.kavin.rocks/streams/$videoId"
        // In real implementation, fetch streams and select best quality
        val mediaItem = MediaItem.fromUri(videoUrl)
        exoPlayer?.setMediaItem(mediaItem)
        exoPlayer?.prepare()
    }

    private fun setupControls() {
        // PiP Button
        findViewById<ImageButton>(R.id.btn_pip)?.setOnClickListener {
            enterPiPMode()
        }

        // Background Play Toggle
        findViewById<ImageButton>(R.id.btn_background)?.setOnClickListener {
            isBackgroundPlayEnabled = !isBackgroundPlayEnabled
            it.isSelected = isBackgroundPlayEnabled
        }

        // Quality Selector
        findViewById<ImageButton>(R.id.btn_quality)?.setOnClickListener {
            showQualitySelector()
        }

        // SponsorBlock Toggle
        findViewById<ImageButton>(R.id.btn_sponsorblock)?.setOnClickListener {
            isSponsorBlockEnabled = !isSponsorBlockEnabled
            it.isSelected = isSponsorBlockEnabled
        }

        // Speed Control
        findViewById<ImageButton>(R.id.btn_speed)?.setOnClickListener {
            showSpeedSelector()
        }

        // Fullscreen toggle
        findViewById<ImageButton>(R.id.btn_fullscreen)?.setOnClickListener {
            toggleFullscreen()
        }

        // Download button
        findViewById<ImageButton>(R.id.btn_download)?.setOnClickListener {
            startDownload()
        }
    }

    private fun startSponsorSkipMonitor() {
        sponsorSkipJob?.cancel()
        if (!isSponsorBlockEnabled || sponsorSegments.isEmpty()) return

        sponsorSkipJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                exoPlayer?.let { player ->
                    val currentPos = player.currentPosition / 1000.0
                    sponsorSegments.forEach { segment ->
                        if (currentPos in segment.startTime..segment.endTime) {
                            player.seekTo((segment.endTime * 1000).toLong())
                            showSkipToast(segment)
                        }
                    }
                }
                delay(100)
            }
        }
    }

    private fun showSkipToast(segment: SponsorSegment) {
        // Show brief toast indicating segment was skipped
    }

    private fun enterPiPMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setAutoEnterEnabled(false)
                        setSeamlessResizeEnabled(true)
                    }
                }
                .build()
            enterPictureInPictureMode(params)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        playerView.useController = !isInPictureInPictureMode
        
        if (isInPictureInPictureMode) {
            // Hide UI elements
            findViewById<LinearLayout>(R.id.controls_overlay)?.visibility = View.GONE
        } else {
            findViewById<LinearLayout>(R.id.controls_overlay)?.visibility = View.VISIBLE
        }
    }

    private fun showQualitySelector() {
        val dialog = BottomSheetDialog(this)
        val view = layoutInflater.inflate(R.layout.dialog_quality_selector, null)
        dialog.setContentView(view)
        
        val qualities = listOf("Auto", "1080p", "720p", "480p", "360p", "240p", "Audio Only")
        val container = view.findViewById<LinearLayout>(R.id.quality_container)
        
        qualities.forEach { quality ->
            val btn = TextView(this).apply {
                text = quality
                textSize = 16f
                setPadding(32, 24, 32, 24)
                setOnClickListener {
                    // Apply quality selection
                    dialog.dismiss()
                }
            }
            container.addView(btn)
        }
        
        dialog.show()
    }

    private fun showSpeedSelector() {
        val dialog = BottomSheetDialog(this)
        val view = layoutInflater.inflate(R.layout.dialog_speed_selector, null)
        dialog.setContentView(view)
        
        val speeds = listOf(0.25f, 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f, 3.0f)
        val container = view.findViewById<LinearLayout>(R.id.speed_container)
        
        speeds.forEach { speed ->
            val btn = TextView(this).apply {
                text = "${speed}x"
                textSize = 16f
                setPadding(32, 24, 32, 24)
                setOnClickListener {
                    exoPlayer?.setPlaybackSpeed(speed)
                    dialog.dismiss()
                }
            }
            container.addView(btn)
        }
        
        dialog.show()
    }

    private fun toggleFullscreen() {
        requestedOrientation = if (requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
    }

    private fun startDownload() {
        // Navigate to download screen
    }

    override fun onStop() {
        super.onStop()
        if (!isInPictureInPictureMode && !isBackgroundPlayEnabled) {
            exoPlayer?.pause()
        }
    }

    override fun onDestroy() {
        sponsorSkipJob?.cancel()
        exoPlayer?.release()
        super.onDestroy()
    }
}
