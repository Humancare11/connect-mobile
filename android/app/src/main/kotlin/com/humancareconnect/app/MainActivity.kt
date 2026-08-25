package com.humancareconnect.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val callForegroundServiceChannel = "com.humancareconnect.app/call_foreground_service"

    // FLAG_SECURE blocks screenshots and screen recording of this app (both
    // by the user and by any other app/malware with screen-capture access)
    // and blanks the app's thumbnail in the Recents/task-switcher view.
    // Applied app-wide rather than per-screen: this is a health-record app
    // where patient name/DOB/medical details can appear on most screens
    // (profile header, appointment details, medical reports, chat), so
    // scoping this to a hand-picked subset of screens risks missing one and
    // silently leaving PHI exposed. Must be set before the window is shown,
    // hence in onCreate() before super.onCreate() inflates the Flutter view.
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

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
