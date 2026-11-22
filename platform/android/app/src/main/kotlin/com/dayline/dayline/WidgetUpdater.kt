package com.dayline.dayline

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

object WidgetUpdater {
    const val ACTION_REFRESH = "com.dayline.dayline.WIDGET_REFRESH"

    /** Redraw every placed widget and arm the next refresh (event start/end or midnight). */
    fun updateAll(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        val snap = WidgetData.load(ctx)
        val now = System.currentTimeMillis()

        val todayIds = mgr.getAppWidgetIds(ComponentName(ctx, TodayWidgetProvider::class.java))
        val agendaIds = mgr.getAppWidgetIds(ComponentName(ctx, AgendaWidgetProvider::class.java))

        for (id in todayIds) mgr.updateAppWidget(id, TodayWidgetProvider.build(ctx, snap, now))
        for (id in agendaIds) mgr.updateAppWidget(id, AgendaWidgetProvider.build(ctx, snap, now))

        if (todayIds.isEmpty() && agendaIds.isEmpty()) cancelRefresh(ctx) else scheduleRefresh(ctx, snap, now)
    }

    private fun refreshIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, TodayWidgetProvider::class.java).setAction(ACTION_REFRESH)
        return PendingIntent.getBroadcast(ctx, 4711, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun cancelRefresh(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(refreshIntent(ctx))
    }

    private fun scheduleRefresh(ctx: Context, snap: WidgetData.Snapshot, now: Long) {
        var next = WidgetData.startOfDay(now, 1) // next midnight
        for (e in snap.events) {
            if (e.start > now && e.start < next) next = e.start
            if (e.end > now && e.end < next) next = e.end
        }
        // Never closer than a minute, so a burst of changes cannot spin the alarm.
        val trigger = maxOf(next + 1000, now + 60_000)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC, trigger, refreshIntent(ctx))
        } catch (_: SecurityException) {
            // The 30-minute system refresh still keeps the widgets reasonably current.
        }
    }
}
