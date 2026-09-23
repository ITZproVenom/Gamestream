package com.gamestream.app

import android.content.Context
import android.os.Build
import android.os.CombinedVibration
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.InputDevice
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Best-effort rumble while streaming.
 * Prefer connected gamepad vibrators; fall back to the device vibrator.
 * Intensity is amplified for weak wired pads via AppearancePrefs.rumbleIntensity.
 */
class ControllerRumble(private val context: Context) {
    private val appearance = AppearancePrefs.get(context)

    private val deviceVibrator: Vibrator? by lazy {
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

        val amp = amplify(max(weak, strong))
        if (amp < 0.02f) {
            stop()
            return
        }

        val duration = durationMs.coerceIn(40L, 2500L)
        val amplitude = (amp * 255f).roundToInt().coerceIn(1, 255)

        var hitGamepad = false
        try {
            hitGamepad = vibrateGamepads(duration, amplitude)
        } catch (_: Exception) {
        }

        // Always also pulse the phone so feedback is felt even when the pad has no motor API.
        try {
            vibrateOne(deviceVibrator, duration, amplitude)
        } catch (_: Exception) {
            if (!hitGamepad) {
                // fail silent
            }
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
            deviceVibrator?.cancel()
        } catch (_: Exception) {
        }
        try {
            for (id in InputDevice.getDeviceIds()) {
                val device = InputDevice.getDevice(id) ?: continue
                if (!isGamepad(device)) continue
                cancelDevice(device)
            }
        } catch (_: Exception) {
        }
    }

    private fun amplify(raw: Float): Float {
        val r = raw.coerceIn(0f, 1f)
        if (r < 0.008f) return 0f
        val gain = 2.6f * appearance.rumbleIntensity.coerceIn(0.5f, 3f)
        return min(1f, max(r * gain, 0.4f * appearance.rumbleIntensity.coerceIn(0.5f, 3f)))
    }

    private fun isGamepad(device: InputDevice): Boolean {
        val sources = device.sources
        return (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
    }

    private fun vibrateGamepads(duration: Long, amplitude: Int): Boolean {
        var any = false
        for (id in InputDevice.getDeviceIds()) {
            val device = InputDevice.getDevice(id) ?: continue
            if (!isGamepad(device)) continue
            if (vibrateDevice(device, duration, amplitude)) any = true
        }
        return any
    }

    private fun vibrateDevice(device: InputDevice, duration: Long, amplitude: Int): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = device.vibratorManager ?: return false
                val ids = mgr.vibratorIds
                if (ids.isEmpty()) return false
                val effect = VibrationEffect.createOneShot(duration, amplitude)
                mgr.vibrate(CombinedVibration.createParallel(effect))
                true
            } else {
                @Suppress("DEPRECATION")
                val v = device.vibrator ?: return false
                if (!v.hasVibrator()) return false
                vibrateOne(v, duration, amplitude)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun cancelDevice(device: InputDevice) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                device.vibratorManager?.cancel()
            } else {
                @Suppress("DEPRECATION")
                device.vibrator?.cancel()
            }
        } catch (_: Exception) {
        }
    }

    private fun vibrateOne(v: Vibrator?, duration: Long, amplitude: Int) {
        if (v == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(duration, amplitude))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(duration)
        }
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
