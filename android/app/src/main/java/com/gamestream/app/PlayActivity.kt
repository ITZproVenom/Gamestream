package com.gamestream.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

data class PlayStat(
    val id: String,
    val title: String,
    var totalSeconds: Long,
    var sessionCount: Int,
    var lastPlayed: Long,
    var weekSeconds: Long,
    var weekAnchor: Long
)

class PlayActivity private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("gamestream", Context.MODE_PRIVATE)
    private val stats = linkedMapOf<String, PlayStat>()
    private var activeId: String? = null
    private var activeStart: Long = 0L

    init {
        val raw = prefs.getString(KEY, null)
        if (!raw.isNullOrBlank()) {
            runCatching {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val id = o.optString("id")
                    if (id.isBlank()) continue
                    stats[id] = PlayStat(
                        id = id,
                        title = o.optString("title"),
                        totalSeconds = o.optLong("totalSeconds"),
                        sessionCount = o.optInt("sessionCount"),
                        lastPlayed = o.optLong("lastPlayed"),
                        weekSeconds = o.optLong("weekSeconds"),
                        weekAnchor = o.optLong("weekAnchor")
                    )
                }
            }
        }
        normalizeWeeks()
    }

    fun begin(id: String, title: String) {
        end()
        if (id.isBlank()) return
        activeId = id
        activeStart = System.currentTimeMillis()
        if (!stats.containsKey(id)) {
            stats[id] = PlayStat(id, title, 0, 0, activeStart, 0, startOfWeek())
            persist()
        }
    }

    fun end() {
        val id = activeId ?: return
        val start = activeStart
        activeId = null
        activeStart = 0L
        val elapsed = ((System.currentTimeMillis() - start) / 1000L).coerceAtLeast(0)
        if (elapsed < 20) return
        normalizeWeeks()
        val existing = stats[id] ?: return
        existing.totalSeconds += elapsed
        existing.weekSeconds += elapsed
        existing.sessionCount += 1
        existing.lastPlayed = System.currentTimeMillis()
        persist()
    }

    fun weekTotal(): Long {
        normalizeWeeks()
        return stats.values.sumOf { it.weekSeconds } + liveSeconds()
    }

    fun rankedThisWeek(): List<PlayStat> {
        normalizeWeeks()
        return stats.values
            .map { it.copy(weekSeconds = it.weekSeconds + if (it.id == activeId) liveSeconds() else 0) }
            .filter { it.weekSeconds > 0 }
            .sortedByDescending { it.weekSeconds }
    }

    fun stat(id: String): PlayStat? = stats[id]

    fun liveSeconds(): Long {
        val start = activeStart
        if (activeId == null || start == 0L) return 0
        return ((System.currentTimeMillis() - start) / 1000L).coerceAtLeast(0)
    }

    fun format(seconds: Long): String {
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        return if (hours > 0) "${hours}h ${minutes}m" else if (minutes > 0) "${minutes}m" else "${seconds % 60}s"
    }

    fun gamesForHub(): List<CatalogGame> =
        rankedThisWeek().mapNotNull { stat -> GameCatalog.games.find { it.id == stat.id } ?: GameCatalog.games.find { it.title.equals(stat.title, true) } }

    private fun normalizeWeeks() {
        val anchor = startOfWeek()
        var changed = false
        stats.values.forEach {
            if (it.weekAnchor < anchor) {
                it.weekSeconds = 0
                it.weekAnchor = anchor
                changed = true
            }
        }
        if (changed) persist()
    }

    private fun persist() {
        val arr = JSONArray()
        stats.values.forEach { stat ->
            arr.put(JSONObject().apply {
                put("id", stat.id)
                put("title", stat.title)
                put("totalSeconds", stat.totalSeconds)
                put("sessionCount", stat.sessionCount)
                put("lastPlayed", stat.lastPlayed)
                put("weekSeconds", stat.weekSeconds)
                put("weekAnchor", stat.weekAnchor)
            })
        }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    private fun startOfWeek(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.DAY_OF_WEEK, cal.firstDayOfWeek)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    companion object {
        private const val KEY = "play_activity_v1"
        @Volatile private var instance: PlayActivity? = null
        fun get(context: Context): PlayActivity =
            instance ?: synchronized(this) {
                instance ?: PlayActivity(context.applicationContext).also { instance = it }
            }
    }
}
