package com.gamestream.app.ui

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

private object OpeningIntroSound {
    fun play() {
        Thread {
            try {
                val rate = 44100
                val duration = 2.05
                val count = (rate * duration).toInt()
                val pcm = ShortArray(count)
                for (i in 0 until count) {
                    val t = i.toDouble() / rate
                    var v = 0.0
                    val notes = arrayOf(
                        doubleArrayOf(0.00, 130.81, 0.22),
                        doubleArrayOf(0.24, 196.00, 0.15),
                        doubleArrayOf(0.48, 261.63, 0.11),
                        doubleArrayOf(0.72, 523.25, 0.045)
                    )
                    for (n in notes) if (t >= n[0]) {
                        val attack = min(1.0, (t - n[0]) / 0.12)
                        val release = max(0.0, min(1.0, (duration - t) / 0.55))
                        v += sin(2.0 * PI * n[1] * t) * n[2] * attack * release
                    }
                    if (t < 0.42) v += sin(2.0 * PI * 65.0 * t) * 0.30 * exp(-t * 7.5)
                    val master = min(1.0, t / 0.06) * max(0.0, min(1.0, (duration - t) / 0.4))
                    pcm[i] = (v * master * 0.82 * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }
                val minBuffer = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(max(minBuffer, pcm.size * 2))
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()
                track.write(pcm, 0, pcm.size)
                track.play()
                Thread.sleep(2100)
                track.stop()
                track.release()
            } catch (_: Throwable) {
                // Decorative audio must never affect app launch.
            }
        }.start()
    }
}

@Composable
fun OpeningIntroOverlay(onFinished: () -> Unit) {
    var visible by remember { mutableStateOf(false) }
    val scale = remember { Animatable(0.78f) }

    LaunchedEffect(Unit) {
        OpeningIntroSound.play()
        visible = true
        scale.animateTo(1f, tween(550))
        delay(1500)
        visible = false
        delay(300)
        onFinished()
    }

    Box(
        Modifier.fillMaxSize().background(Color.Black),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.scale(scale.value)
        ) {
            Box(
                Modifier.size(82.dp).background(Color(0x14FFFFFF), RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.SportsEsports, contentDescription = null, tint = Color.White, modifier = Modifier.size(38.dp))
            }
            Text("GAMESTREAM", color = Color.White, fontSize = 25.sp, fontWeight = FontWeight.Black, letterSpacing = 4.sp)
        }
    }
}
