package app.doscreen.doscreen

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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ScreenCaptureService : Service() {
    companion object {
        const val CHANNEL_ID = "doscreen_media_projection"
        const val NOTIFICATION_ID = 41337
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DoScreen Canlı Yayın",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("DoScreen Yayında")
            .setContentText("Ekranınız kablosuz olarak paylaşılıyor.")
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(
                NOTIFICATION_ID,
                notification,
                serviceType
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
        super.onDestroy()
    }
}

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app.doscreen/media_projection_service"
    private val AIRPLAY_CHANNEL = "app.doscreen/airplay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, ScreenCaptureService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    val intent = Intent(this, ScreenCaptureService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "requestAudioPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 101)
                        }
                    }
                    result.success(true)
                }
                "hasAudioPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    } else {
                        true
                    }
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        }

        val airplayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AIRPLAY_CHANNEL)
        AirPlayManager.onStateChangedCallback = { statusMap ->
            airplayChannel.invokeMethod("onAirPlayStateChanged", statusMap)
        }

        airplayChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startReceiver" -> {
                    val name = call.argument<String>("name") ?: "DoScreen TV"
                    AirPlayManager.start(this, name)
                    result.success(AirPlayManager.getStatusMap())
                }
                "stopReceiver" -> {
                    AirPlayManager.stop()
                    result.success(AirPlayManager.getStatusMap())
                }
                "getStatus" -> {
                    result.success(AirPlayManager.getStatusMap())
                }
                else -> result.notImplemented()
            }
        }
    }
}

