package com.dayline.dayline

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

/** A list of what is coming up over the next days. */
class AgendaWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetUpdater.updateAll(context)
    }

    companion object {
        private const val ROWS = 5

        private val rowIds = intArrayOf(R.id.agenda_row1, R.id.agenda_row2, R.id.agenda_row3, R.id.agenda_row4, R.id.agenda_row5)
        private val dotIds = intArrayOf(R.id.agenda_dot1, R.id.agenda_dot2, R.id.agenda_dot3, R.id.agenda_dot4, R.id.agenda_dot5)
        private val whenIds = intArrayOf(R.id.agenda_when1, R.id.agenda_when2, R.id.agenda_when3, R.id.agenda_when4, R.id.agenda_when5)
        private val titleIds = intArrayOf(R.id.agenda_title1, R.id.agenda_title2, R.id.agenda_title3, R.id.agenda_title4, R.id.agenda_title5)

        fun build(ctx: Context, snap: WidgetData.Snapshot, now: Long): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_agenda)

            val iran = snap.iran[WidgetData.dayKey(now)]
            val header = WidgetData.fmt(now, "EEEE d MMMM")
            rv.setTextViewText(R.id.agenda_header, header)
            if (iran.isNullOrEmpty()) {
                rv.setViewVisibility(R.id.agenda_iran, View.GONE)
            } else {
                rv.setViewVisibility(R.id.agenda_iran, View.VISIBLE)
                rv.setTextViewText(R.id.agenda_iran, iran)
            }

            val todayStart = WidgetData.startOfDay(now)
            val tomorrowStart = WidgetData.startOfDay(now, 1)
            val dayAfter = WidgetData.startOfDay(now, 2)

            // Anything not finished yet (all-day events count for their whole day).
            val upcoming = snap.events
                .filter { if (it.allDay) it.end > todayStart else it.end > now || (it.end <= it.start && it.start >= now) }
                .take(ROWS)

            for (i in 0 until ROWS) {
                if (i >= upcoming.size) {
                    if (i == 0) {
                        rv.setViewVisibility(rowIds[0], View.VISIBLE)
                        rv.setTextViewText(whenIds[0], "")
                        rv.setTextViewText(dotIds[0], "")
                        rv.setTextViewText(titleIds[0], "Nothing coming up")
                        rv.setTextColor(titleIds[0], 0xFF8F96A8.toInt())
                    } else {
                        rv.setViewVisibility(rowIds[i], View.GONE)
                    }
                    continue
                }
                val e = upcoming[i]
                rv.setViewVisibility(rowIds[i], View.VISIBLE)
                rv.setTextViewText(dotIds[i], "●")
                rv.setTextColor(dotIds[i], e.color)

                val dayLabel = when {
                    e.start < tomorrowStart -> "Today"
                    e.start < dayAfter -> "Tomorrow"
                    else -> WidgetData.fmt(e.start, "EEE d")
                }
                val whenText = if (e.allDay) "$dayLabel · all day"
                else if (e.start <= now) "Now"
                else "$dayLabel ${WidgetData.clock(e.start, snap.use24h)}"
                rv.setTextViewText(whenIds[i], whenText)
                rv.setTextViewText(titleIds[i], e.title)
                rv.setTextColor(titleIds[i], Color.WHITE)
            }

            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    ctx, 1, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                rv.setOnClickPendingIntent(R.id.widget_root, pi)
            }
            return rv
        }
    }
}
