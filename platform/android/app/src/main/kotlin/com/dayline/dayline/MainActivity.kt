package com.dayline.dayline

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Flutter sends the next two weeks of events here; the widgets draw from this copy,
        // so they stay correct even when the app is closed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dayline/widgets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val events = call.argument<String>("events") ?: "[]"
                        val iran = call.argument<String>("iran") ?: "{}"
                        val use24h = call.argument<Boolean>("use24h") ?: true
                        WidgetData.save(applicationContext, events, iran, use24h)
                        WidgetUpdater.updateAll(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
