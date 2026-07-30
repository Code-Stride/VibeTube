package com.blazenxt.vibetube.utils

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "vibetube_prefs")

@Singleton
class PreferenceManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val dataStore = context.dataStore

    // Dark Mode
    private val DARK_MODE = booleanPreferencesKey("dark_mode")
    fun isDarkModeEnabled(): Flow<Boolean> = dataStore.data.map { it[DARK_MODE] ?: true }
    suspend fun setDarkMode(enabled: Boolean) = dataStore.edit { it[DARK_MODE] = enabled }

    // SponsorBlock
    private val SPONSOR_BLOCK = booleanPreferencesKey("sponsor_block")
    fun isSponsorBlockEnabled(): Flow<Boolean> = dataStore.data.map { it[SPONSOR_BLOCK] ?: true }
    suspend fun setSponsorBlock(enabled: Boolean) = dataStore.edit { it[SPONSOR_BLOCK] = enabled }

    // SponsorBlock Categories
    private val SB_SPONSOR = booleanPreferencesKey("sb_sponsor")
    private val SB_SELFPROMO = booleanPreferencesKey("sb_selfpromo")
    private val SB_INTERACTION = booleanPreferencesKey("sb_interaction")
    private val SB_INTRO = booleanPreferencesKey("sb_intro")
    private val SB_OUTRO = booleanPreferencesKey("sb_outro")
    private val SB_PREVIEW = booleanPreferencesKey("sb_preview")
    private val SB_FILLER = booleanPreferencesKey("sb_filler")

    fun getSBCategories(): Flow<Map<String, Boolean>> = dataStore.data.map { prefs ->
        mapOf(
            "sponsor" to (prefs[SB_SPONSOR] ?: true),
            "selfpromo" to (prefs[SB_SELFPROMO] ?: true),
            "interaction" to (prefs[SB_INTERACTION] ?: true),
            "intro" to (prefs[SB_INTRO] ?: false),
            "outro" to (prefs[SB_OUTRO] ?: false),
            "preview" to (prefs[SB_PREVIEW] ?: false),
            "filler" to (prefs[SB_FILLER] ?: false)
        )
    }

    // Background Play
    private val BACKGROUND_PLAY = booleanPreferencesKey("background_play")
    fun isBackgroundPlayEnabled(): Flow<Boolean> = dataStore.data.map { it[BACKGROUND_PLAY] ?: true }
    suspend fun setBackgroundPlay(enabled: Boolean) = dataStore.edit { it[BACKGROUND_PLAY] = enabled }

    // Auto PiP
    private val AUTO_PIP = booleanPreferencesKey("auto_pip")
    fun isAutoPipEnabled(): Flow<Boolean> = dataStore.data.map { it[AUTO_PIP] ?: true }
    suspend fun setAutoPip(enabled: Boolean) = dataStore.edit { it[AUTO_PIP] = enabled }

    // Default Quality
    private val DEFAULT_QUALITY = stringPreferencesKey("default_quality")
    fun getDefaultQuality(): Flow<String> = dataStore.data.map { it[DEFAULT_QUALITY] ?: "720p" }
    suspend fun setDefaultQuality(quality: String) = dataStore.edit { it[DEFAULT_QUALITY] = quality }

    // Default Playback Speed
    private val DEFAULT_SPEED = floatPreferencesKey("default_speed")
    fun getDefaultSpeed(): Flow<Float> = dataStore.data.map { it[DEFAULT_SPEED] ?: 1.0f }
    suspend fun setDefaultSpeed(speed: Float) = dataStore.edit { it[DEFAULT_SPEED] = speed }

    // Download Quality
    private val DOWNLOAD_QUALITY = stringPreferencesKey("download_quality")
    fun getDownloadQuality(): Flow<String> = dataStore.data.map { it[DOWNLOAD_QUALITY] ?: "720p" }
    suspend fun setDownloadQuality(quality: String) = dataStore.edit { it[DOWNLOAD_QUALITY] = quality }

    // Download over WiFi only
    private val DOWNLOAD_WIFI_ONLY = booleanPreferencesKey("download_wifi_only")
    fun isDownloadWifiOnly(): Flow<Boolean> = dataStore.data.map { it[DOWNLOAD_WIFI_ONLY] ?: false }
    suspend fun setDownloadWifiOnly(enabled: Boolean) = dataStore.edit { it[DOWNLOAD_WIFI_ONLY] = enabled }

    // Ad Block
    private val AD_BLOCK = booleanPreferencesKey("ad_block")
    fun isAdBlockEnabled(): Flow<Boolean> = dataStore.data.map { it[AD_BLOCK] ?: true }
    suspend fun setAdBlock(enabled: Boolean) = dataStore.edit { it[AD_BLOCK] = enabled }

    // Homepage Layout
    private val HOME_LAYOUT = stringPreferencesKey("home_layout")
    fun getHomeLayout(): Flow<String> = dataStore.data.map { it[HOME_LAYOUT] ?: "grid" }
    suspend fun setHomeLayout(layout: String) = dataStore.edit { it[HOME_LAYOUT] = layout }

    // Search History
    private val SEARCH_HISTORY = stringSetPreferencesKey("search_history")
    fun getSearchHistory(): Flow<Set<String>> = dataStore.data.map { it[SEARCH_HISTORY] ?: emptySet() }
    suspend fun addToSearchHistory(query: String) {
        dataStore.edit { prefs ->
            val history = prefs[SEARCH_HISTORY]?.toMutableSet() ?: mutableSetOf()
            history.add(query)
            if (history.size > 20) {
                val sorted = history.toList().takeLast(20)
                prefs[SEARCH_HISTORY] = sorted.toSet()
            } else {
                prefs[SEARCH_HISTORY] = history
            }
        }
    }
    suspend fun clearSearchHistory() = dataStore.edit { it.remove(SEARCH_HISTORY) }

    // Country/Region
    private val REGION = stringPreferencesKey("region")
    fun getRegion(): Flow<String> = dataStore.data.map { it[REGION] ?: "US" }
    suspend fun setRegion(region: String) = dataStore.edit { it[REGION] = region }

    // Language
    private val LANGUAGE = stringPreferencesKey("language")
    fun getLanguage(): Flow<String> = dataStore.data.map { it[LANGUAGE] ?: "en" }
    suspend fun setLanguage(language: String) = dataStore.edit { it[LANGUAGE] = language }

    // Proxy
    private val PROXY_ENABLED = booleanPreferencesKey("proxy_enabled")
    private val PROXY_URL = stringPreferencesKey("proxy_url")
    fun isProxyEnabled(): Flow<Boolean> = dataStore.data.map { it[PROXY_ENABLED] ?: false }
    fun getProxyUrl(): Flow<String> = dataStore.data.map { it[PROXY_URL] ?: "" }
    suspend fun setProxy(enabled: Boolean, url: String) = dataStore.edit {
        it[PROXY_ENABLED] = enabled
        it[PROXY_URL] = url
    }

    // Return YouTube Dislike
    private val RETURN_YT_DISLIKE = booleanPreferencesKey("return_yt_dislike")
    fun isReturnDislikeEnabled(): Flow<Boolean> = dataStore.data.map { it[RETURN_YT_DISLIKE] ?: true }
    suspend fun setReturnDislike(enabled: Boolean) = dataStore.edit { it[RETURN_YT_DISLIKE] = enabled }
}
