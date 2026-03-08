package com.example.chitose_bus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class BusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.bus_widget_layout)

            val nextBusTime = widgetData.getString("nextBusTime", "--:--") ?: "--:--"
            val direction = widgetData.getString("nextBusDirection", "読み込み中...") ?: "読み込み中..."
            val destination = widgetData.getString("nextBusDestination", "") ?: ""
            val updatedAtIso = widgetData.getString("updatedAt", "") ?: ""

            views.setTextViewText(R.id.widget_time, nextBusTime)
            views.setTextViewText(R.id.widget_direction, direction)
            views.setTextViewText(R.id.widget_destination, destination)

            val formattedUpdated = if (updatedAtIso.isNotEmpty()) {
                try {
                    val instant = java.time.Instant.parse(updatedAtIso)
                    val sdf = SimpleDateFormat("HH:mm", Locale.JAPAN).apply {
                        timeZone = TimeZone.getTimeZone("Asia/Tokyo")
                    }
                    "更新: ${sdf.format(Date.from(instant))}"
                } catch (e: Exception) {
                    ""
                }
            } else ""
            views.setTextViewText(R.id.widget_updated, formattedUpdated)

            // タップでアプリ起動
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
