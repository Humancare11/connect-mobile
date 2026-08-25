package com.humancareconnect.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service whose only job is to keep this process (and
 * therefore the active socket + RTCPeerConnection) alive while a video
 * consultation is ongoing and the app is backgrounded — screen lock,
 * switching apps, or a brief background window during a Wi-Fi/cellular
 * handoff. Without a foreground service, Android — especially aggressive OEM
 * battery managers (Xiaomi/Oppo/Huawei/Samsung) — can suspend background
 * networking mid-call.
 *
 * Typed "camera|microphone" rather than "mediaProjection", matching what a
 * plain audio/video call actually uses.
 *
 * Started/stopped from Dart via MainActivity's method channel — see
 * lib/services/call_foreground_service.dart.
 */
class CallForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "video_call_ongoing"
        private const val NOTIFICATION_ID = 4201
        private const val EXTRA_HAS_AUDIO = "hasAudio"
        private const val EXTRA_HAS_VIDEO = "hasVideo"

        fun start(context: Context, hasAudio: Boolean, hasVideo: Boolean) {
            val intent = Intent(context, CallForegroundService::class.java)
            intent.putExtra(EXTRA_HAS_AUDIO, hasAudio)
            intent.putExtra(EXTRA_HAS_VIDEO, hasVideo)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Defaults to true/true (rather than false/false) so this never skips
        // calling startForeground() if the extras are ever missing for some
        // reason — a service started via startForegroundService() that never
        // calls startForeground() crashes the whole app.
        val hasAudio = intent?.getBooleanExtra(EXTRA_HAS_AUDIO, true) ?: true
        val hasVideo = intent?.getBooleanExtra(EXTRA_HAS_VIDEO, false) ?: false
        postForegroundNotification(hasAudio, hasVideo)
        return START_NOT_STICKY
    }

    private fun postForegroundNotification(hasAudio: Boolean, hasVideo: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Video consultation",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            manager?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Humancare Connect")
            .setContentText("Video consultation in progress")
            // applicationInfo.icon is the full-color launcher icon, which the
            // status bar renders as a solid white/grey blob (Android draws
            // small icons as an alpha-mask silhouette, ignoring color) — use
            // the dedicated monochrome asset instead, same as notification_service.dart.
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // The type passed here must be a subset of the manifest's
            // foregroundServiceType for this service ("camera|microphone");
            // only the types backed by a track this call actually acquired
            // (and was therefore already granted runtime permission for) are
            // requested, so this never claims a type without its permission.
            var type = 0
            if (hasVideo) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (hasAudio) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (type == 0) type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
