package com.dayline.dayline

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

/** A compact "today at a glance" widget: the date, what is on now or next, and how busy the day is. */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetUpdater.updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WidgetUpdater.ACTION_REFRESH,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED -> WidgetUpdater.updateAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        private const val ACCENT = 0xFF8FA8FF.toInt()

        fun build(ctx: Context, snap: WidgetData.Snapshot, now: Long): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_today)

            rv.setTextViewText(R.id.today_weekday, WidgetData.fmt(now, "EEE").uppercase())
            rv.setTextViewText(R.id.today_day, WidgetData.fmt(now, "d"))
            rv.setTextViewText(R.id.today_month, WidgetData.fmt(now, "MMM yyyy"))

            val iran = snap.iran[WidgetData.dayKey(now)]
            if (iran.isNullOrEmpty()) {
                rv.setViewVisibility(R.id.today_iran, View.GONE)
            } else {
                rv.setViewVisibility(R.id.today_iran, View.VISIBLE)
                rv.setTextViewText(R.id.today_iran, iran)
            }

            val from = WidgetData.startOfDay(now)
            val to = WidgetData.startOfDay(now, 1)
            val today = snap.events.filter { WidgetData.overlaps(it, from, to) }
            val timedLeft = today.filter { !it.allDay && it.end > now || (!it.allDay && it.end <= it.start && it.start >= now) }

            val focus = timedLeft.firstOrNull()
            if (focus != null) {
                val live = focus.start <= now
                rv.setTextViewText(
                    R.id.today_label,
                    if (live) "NOW" else "NEXT · " + WidgetData.clock(focus.start, snap.use24h),
                )
                rv.setTextViewText(R.id.today_title, focus.title)
                rv.setTextColor(R.id.today_title, Color.WHITE)
                val sub = if (live) "until " + WidgetData.clock(focus.end, snap.use24h) else focus.location
                rv.setTextViewText(R.id.today_sub, sub)
                rv.setViewVisibility(R.id.today_sub, if (sub.isEmpty()) View.GONE else View.VISIBLE)
            } else {
                rv.setTextViewText(R.id.today_label, if (today.isEmpty()) "FREE DAY" else "ALL DONE")
                rv.setTextViewText(
                    R.id.today_title,
                    if (today.isEmpty()) "Nothing planned" else today.first().title,
                )
                rv.setTextColor(R.id.today_title, Color.WHITE)
                rv.setViewVisibility(R.id.today_sub, View.GONE)
            }

            val count = today.size
            rv.setTextViewText(
                R.id.today_count,
                when (count) {
                    0 -> ""
                    1 -> "1 event today"
                    else -> "$count events today"
                },
            )
            rv.setTextColor(R.id.today_label, ACCENT)

            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    ctx, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                rv.setOnClickPendingIntent(R.id.widget_root, pi)
            }
            return rv
        }
    }
}
