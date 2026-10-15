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
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                "SpanCast Canlı Yayın",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SpanCast Yayında")
            .setContentText("Ekranınız kablosuz olarak paylaşılıyor.")
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            android.util.Log.e("ScreenCaptureService", "startForeground error, trying fallback: ${e.message}")
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (e2: Exception) {
                android.util.Log.e("ScreenCaptureService", "fallback startForeground error: ${e2.message}")
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            android.util.Log.e("ScreenCaptureService", "stopForeground error: ${e.message}")
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
                    try {
                        val intent = Intent(this, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "startService error: ${e.message}")
                        result.success(false)
                    }
                }
                "stopService" -> {
                    try {
                        val intent = Intent(this, ScreenCaptureService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
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
                    val name = call.argument<String>("name") ?: "SpanCast TV"
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

        val updaterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.spancast/updater")
        updaterChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "File path is null or empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

