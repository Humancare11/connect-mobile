package com.humancareconnect.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val callForegroundServiceChannel = "com.humancareconnect.app/call_foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callForegroundServiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val hasAudio = call.argument<Boolean>("hasAudio") ?: true
                        val hasVideo = call.argument<Boolean>("hasVideo") ?: false
                        CallForegroundService.start(applicationContext, hasAudio, hasVideo)
                        result.success(null)
                    }
                    "stop" -> {
                        CallForegroundService.stop(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
