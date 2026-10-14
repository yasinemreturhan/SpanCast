package app.doscreen.doscreen

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.Surface
import dev.imirror.receiver.airplay.AirPlayReceiver
import dev.imirror.receiver.service.ProtocolState
import dev.imirror.receiver.util.Logger

/**
 * AirPlayManager — Bridge between Flutter and the native AirPlay 2 receiver engine.
 */
object AirPlayManager {

    private var airPlayReceiver: AirPlayReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    var currentSurface: Surface? = null
        private set

    @Volatile
    var isRunning: Boolean = false
        private set

    @Volatile
    var currentStatus: String = "IDLE"
        private set

    @Volatile
    var activeSenderName: String? = null
        private set

    @Volatile
    var currentDeviceName: String = "DoScreen TV"
        private set

    var onStateChangedCallback: ((Map<String, Any?>) -> Unit)? = null

    fun start(context: Context, displayName: String = "DoScreen TV") {
        if (isRunning) {
            Logger.i("AirPlayManager: already running")
            return
        }

        currentDeviceName = displayName.ifBlank { "DoScreen TV" }
        Logger.i("AirPlayManager: starting receiver with name '$currentDeviceName'")

        val appContext = context.applicationContext

        airPlayReceiver = AirPlayReceiver(
            context = appContext,
            displayName = currentDeviceName,
            mirrorWidth = 1920,
            mirrorHeight = 1080,
            audioEnabled = true,
            pinAuthEnabled = false,
            videoSurfaceProvider = { currentSurface },
            onStateChanged = { protocolState ->
                currentStatus = protocolState.name
                Logger.i("AirPlayManager: state changed to ${protocolState.name}")

                mainHandler.post {
                    notifyFlutter()

                    if (protocolState == ProtocolState.CONNECTED) {
                        launchPlayerActivity(appContext)
                    } else if (protocolState == ProtocolState.ADVERTISING || protocolState == ProtocolState.DISABLED) {
                        AirPlayActivity.instance?.finish()
                    }
                }
            },
            onSenderNameChanged = { sender ->
                activeSenderName = sender
                Logger.i("AirPlayManager: sender name received: '$sender'")
                mainHandler.post { notifyFlutter() }
            },
            onActualNameRegistered = { actualName ->
                currentDeviceName = actualName
                Logger.i("AirPlayManager: actual mDNS name registered: '$actualName'")
                mainHandler.post { notifyFlutter() }
            }
        )

        try {
            airPlayReceiver?.start()
            isRunning = true
            currentStatus = "ADVERTISING"
            notifyFlutter()
        } catch (e: Exception) {
            Logger.e("AirPlayManager: failed to start AirPlay receiver", e)
            currentStatus = "ERROR"
            isRunning = false
            notifyFlutter()
        }
    }

    fun stop() {
        if (!isRunning) return
        Logger.i("AirPlayManager: stopping receiver")

        try {
            airPlayReceiver?.stop()
        } catch (e: Exception) {
            Logger.e("AirPlayManager: error stopping receiver", e)
        }

        airPlayReceiver = null
        isRunning = false
        currentStatus = "IDLE"
        activeSenderName = null
        currentSurface = null

        mainHandler.post {
            AirPlayActivity.instance?.finish()
            notifyFlutter()
        }
    }

    private fun launchPlayerActivity(context: Context) {
        if (AirPlayActivity.instance != null) {
            Logger.d("AirPlayManager: AirPlayActivity is already running")
            return
        }

        Logger.i("AirPlayManager: launching AirPlayActivity for full-screen display")
        val intent = Intent(context, AirPlayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        context.startActivity(intent)
    }

    fun onSurfaceCreated(surface: Surface) {
        Logger.i("AirPlayManager: Surface created and available for decoding")
        currentSurface = surface
    }

    fun onSurfaceChanged(surface: Surface, width: Int, height: Int) {
        Logger.d("AirPlayManager: Surface changed: ${width}x${height}")
        currentSurface = surface
    }

    fun onSurfaceDestroyed() {
        Logger.i("AirPlayManager: Surface destroyed")
        currentSurface = null
    }

    fun getStatusMap(): Map<String, Any?> {
        return mapOf(
            "isRunning" to isRunning,
            "status" to currentStatus,
            "deviceName" to currentDeviceName,
            "activeSender" to activeSenderName
        )
    }

    private fun notifyFlutter() {
        onStateChangedCallback?.invoke(getStatusMap())
    }
}
