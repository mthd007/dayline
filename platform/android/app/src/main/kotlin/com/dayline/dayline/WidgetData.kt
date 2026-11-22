package com.dayline.dayline

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** Events pushed from Flutter, stored in SharedPreferences for the widgets. */
object WidgetData {
    private const val PREFS = "dayline_widgets"

    data class Ev(
        val title: String,
        val start: Long,
        val end: Long,
        val allDay: Boolean,
        val color: Int,
        val location: String,
    )

    class Snapshot(
        val events: List<Ev>,
        val iran: Map<String, String>,
        val use24h: Boolean,
    )

    fun save(ctx: Context, events: String, iran: String, use24h: Boolean) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("events", events)
            .putString("iran", iran)
            .putBoolean("use24h", use24h)
            .apply()
    }

    fun load(ctx: Context): Snapshot {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val events = ArrayList<Ev>()
        try {
            val arr = JSONArray(p.getString("events", "[]"))
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                events.add(
                    Ev(
                        title = o.optString("t", ""),
                        start = o.optLong("s"),
                        end = o.optLong("e"),
                        allDay = o.optBoolean("a", false),
                        color = o.optLong("c", 0xFF7C9CFF).toInt(),
                        location = o.optString("l", ""),
                    )
                )
            }
        } catch (_: Exception) {
            // corrupt data: show an empty widget rather than crash
        }
        events.sortBy { it.start }

        val iran = HashMap<String, String>()
        try {
            val o = JSONObject(p.getString("iran", "{}"))
            val keys = o.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                iran[k] = o.optString(k, "")
            }
        } catch (_: Exception) {
        }
        return Snapshot(events, iran, p.getBoolean("use24h", true))
    }

    // ---- time helpers ----------------------------------------------------

    fun startOfDay(millis: Long, plusDays: Int = 0): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = millis
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        c.add(Calendar.DAY_OF_MONTH, plusDays)
        return c.timeInMillis
    }

    fun dayKey(millis: Long): String {
        val c = Calendar.getInstance()
        c.timeInMillis = millis
        return String.format(
            Locale.US, "%04d-%02d-%02d",
            c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH)
        )
    }

    fun overlaps(e: Ev, from: Long, to: Long): Boolean =
        if (e.end <= e.start) e.start in from until to else e.start < to && e.end > from

    fun clock(millis: Long, use24h: Boolean): String {
        val f = if (use24h) SimpleDateFormat("HH:mm", Locale.US) else SimpleDateFormat("h:mm a", Locale.US)
        return f.format(Date(millis))
    }

    fun fmt(millis: Long, pattern: String): String = SimpleDateFormat(pattern, Locale.US).format(Date(millis))
}
