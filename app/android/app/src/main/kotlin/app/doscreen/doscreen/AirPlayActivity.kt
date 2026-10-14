package app.doscreen.doscreen

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.view.animation.AlphaAnimation
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * AirPlayActivity — Full-screen hardware-accelerated video display for AirPlay 2 mirroring.
 *
 * Provides a dedicated SurfaceView for MediaCodec direct rendering.
 * Includes a lightweight non-intrusive status pill that confirms connection and
 * informs the user how to exit.
 */
class AirPlayActivity : Activity(), SurfaceHolder.Callback {

    companion object {
        @Volatile
        var instance: AirPlayActivity? = null
            private set
    }

    private lateinit var surfaceView: SurfaceView
    private lateinit var hudLayout: LinearLayout
    private val handler = Handler(Looper.getMainLooper())
    private val hideHudRunnable = Runnable { hideHud() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // Keep screen on while mirroring
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Immersive fullscreen mode
        hideSystemUI()

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        surfaceView = SurfaceView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
            holder.addCallback(this@AirPlayActivity)
        }
        root.addView(surfaceView)

        // Info HUD overlay at top
        hudLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(40, 24, 40, 24)

            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#CC121826"))
                cornerRadius = 24f
                setStroke(2, Color.parseColor("#334155"))
            }
            background = bg

            val titleView = TextView(this@AirPlayActivity).apply {
                text = "📺 DoScreen • Mac Ekranı Aktif"
                setTextColor(Color.WHITE)
                textSize = 18f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            }

            val subtitleView = TextView(this@AirPlayActivity).apply {
                val sender = AirPlayManager.activeSenderName ?: "Mac"
                text = "$sender bağlandı • Ayrı 2. Ekran veya Yansıtma • Çıkmak için Geri tuşuna basın"
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, 8, 0, 0)
            }

            addView(titleView)
            addView(subtitleView)
        }

        val hudParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = 48
        }
        root.addView(hudLayout, hudParams)

        setContentView(root)

        // Fade HUD out after 4 seconds
        handler.postDelayed(hideHudRunnable, 4000)
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController
            if (controller != null) {
                controller.hide(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
            )
        }
    }

    private fun showHud() {
        handler.removeCallbacks(hideHudRunnable)
        if (hudLayout.visibility != View.VISIBLE) {
            val anim = AlphaAnimation(0f, 1f).apply { duration = 250 }
            hudLayout.startAnimation(anim)
            hudLayout.visibility = View.VISIBLE
        }
        handler.postDelayed(hideHudRunnable, 4000)
    }

    private fun hideHud() {
        if (hudLayout.visibility == View.VISIBLE) {
            val anim = AlphaAnimation(1f, 0f).apply { duration = 300 }
            hudLayout.startAnimation(anim)
            hudLayout.visibility = View.GONE
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> {
                finish()
                return true
            }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                if (hudLayout.visibility == View.VISIBLE) {
                    hideHud()
                } else {
                    showHud()
                }
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        AirPlayManager.onSurfaceCreated(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        AirPlayManager.onSurfaceChanged(holder.surface, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        AirPlayManager.onSurfaceDestroyed()
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(hideHudRunnable)
        if (instance == this) {
            instance = null
        }
        AirPlayManager.onSurfaceDestroyed()
    }
}
