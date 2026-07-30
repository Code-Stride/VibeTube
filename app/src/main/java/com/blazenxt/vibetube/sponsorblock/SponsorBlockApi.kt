package com.blazenxt.vibetube.sponsorblock

import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import javax.inject.Inject
import javax.inject.Singleton

data class SponsorSegment(
    val segment: List<Double>,
    val UUID: String,
    val category: String,
    val actionType: String = "skip",
    val locked: Boolean = false,
    val votes: Int = 0,
    val description: String = ""
) {
    val startTime: Double get() = segment[0]
    val endTime: Double get() = segment[1]
    val duration: Double get() = endTime - startTime

    fun getCategoryLabel(): String {
        return when (category) {
            "sponsor" -> "Sponsor"
            "selfpromo" -> "Self Promotion"
            "interaction" -> "Interaction Reminder"
            "intro" -> "Intro"
            "outro" -> "Outro"
            "preview" -> "Preview"
            "music_offtopic" -> "Non-Music Section"
            "filler" -> "Filler"
            else -> category.replace("_", " ").capitalize()
        }
    }
}

data class SponsorBlockResponse(
    val hash: String,
    val segments: List<SponsorSegment>
)

interface SponsorBlockApiService {
    @GET("skipSegments/{videoId}")
    suspend fun getSegments(
        @Path("videoId") videoId: String,
        @Query("categories") categories: String = """["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]"""
    ): List<SponsorSegmentResponse>
}

data class SponsorSegmentResponse(
    val segment: List<Double>,
    val UUID: String,
    val category: String,
    val actionType: String?,
    val locked: Int?,
    val votes: Int?,
    val videoDuration: Double?,
    val description: String?
)

@Singleton
class SponsorBlockApi @Inject constructor(
    private val apiService: SponsorBlockApiService
) {
    suspend fun getSegments(videoId: String): List<SponsorSegment> {
        return try {
            val response = apiService.getSegments(videoId)
            response.map { resp ->
                SponsorSegment(
                    segment = resp.segment,
                    UUID = resp.UUID,
                    category = resp.category,
                    actionType = resp.actionType ?: "skip",
                    locked = (resp.locked ?: 0) == 1,
                    votes = resp.votes ?: 0,
                    description = resp.description ?: ""
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
