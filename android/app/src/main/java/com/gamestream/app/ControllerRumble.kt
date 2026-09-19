package com.gamestream.app

import android.content.Context
import android.os.Build
import android.os.CombinedVibration
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Best-effort rumble for Android while streaming.
 * Uses the device vibrator (and gamepad vibrators when the system routes them).
 * Intensity is amplified for weak wired pads via AppearancePrefs.rumbleIntensity.
 */
class ControllerRumble(private val context: Context) {
    private val appearance = AppearancePrefs(context)

    private val vibrator: Vibrator? by lazy {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                mgr?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Exception) {
            null
        }
    }

    fun play(weak: Float, strong: Float, durationMs: Long, force: Boolean = false) {
        if (!force && !appearance.controllerHaptics) return
        val v = vibrator ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!v.hasVibrator()) return
        }

        val amp = amplify(max(weak, strong))
        if (amp < 0.02f) {
            stop()
            return
        }

        val duration = durationMs.coerceIn(40L, 2500L)
        val amplitude = (amp * 255f).roundToInt().coerceIn(1, 255)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                val effect = VibrationEffect.createOneShot(duration, amplitude)
                mgr?.vibrate(CombinedVibration.createParallel(effect))
                    ?: v.vibrate(effect)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createOneShot(duration, amplitude))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(duration)
            }
        } catch (_: Exception) {
            // fail silent
        }
    }

    fun playTest() {
        play(1f, 1f, 420, force = true)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            play(0.9f, 1f, 300, force = true)
        }, 450)
    }

    fun stop() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
    }

    private fun amplify(raw: Float): Float {
        val r = raw.coerceIn(0f, 1f)
        if (r < 0.008f) return 0f
        val gain = 2.6f * appearance.rumbleIntensity.coerceIn(0.5f, 3f)
        return min(1f, max(r * gain, 0.4f * appearance.rumbleIntensity.coerceIn(0.5f, 3f)))
    }

    companion object {
        @Volatile private var instance: ControllerRumble? = null

        fun get(context: Context): ControllerRumble {
            val app = context.applicationContext
            return instance ?: synchronized(this) {
                instance ?: ControllerRumble(app).also { instance = it }
            }
        }
    }
}
