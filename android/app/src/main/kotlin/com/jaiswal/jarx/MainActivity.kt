package com.jaiswal.jarx

import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.Visualizer
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// The launcher screen. AudioServiceActivity shares audio_service's Flutter
// engine, so the UI and background playback stay one app.
class MainActivity : AudioServiceActivity() {
    private var visualizer: Visualizer? = null

    // Offers JARX's audio session to equalizer apps, takes it back, or opens
    // the installed equalizer's panel. PlayerEngine decides when.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Restarts the app process: the only way to reopen a database left
        // locked by an earlier engine in this process (see AppRestart in Dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarx/app")
            .setMethodCallHandler { call, result ->
                if (call.method != "restart") return@setMethodCallHandler result.notImplemented()
                result.success(null)
                packageManager.getLaunchIntentForPackage(packageName)?.let {
                    startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
                }
                android.os.Process.killProcess(android.os.Process.myPid())
            }
        // Live visualizer: waveform and FFT of JARX's own audio session, ~20 per
        // second. The argument is the session id. Needs RECORD_AUDIO.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "jarx/visualizer")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    releaseVisualizer()
                    try {
                        val v = Visualizer(args as Int)
                        v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(512)
                        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                            override fun onWaveFormDataCapture(vis: Visualizer, wave: ByteArray, rate: Int) {
                                events.success(mapOf("wave" to wave))
                            }
                            override fun onFftDataCapture(vis: Visualizer, fft: ByteArray, rate: Int) {
                                events.success(mapOf("fft" to fft))
                            }
                        }, Visualizer.getMaxCaptureRate(), true, true)
                        v.enabled = true
                        visualizer = v
                    } catch (e: Exception) {
                        events.error("visualizer", e.message, null)
                    }
                }

                override fun onCancel(args: Any?) = releaseVisualizer()
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarx/audio_effects")
            .setMethodCallHandler { call, result ->
                val session = call.arguments as Int
                fun intent(action: String) = Intent(action)
                    .putExtra(AudioEffect.EXTRA_AUDIO_SESSION, session)
                    .putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                    .putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                when (call.method) {
                    "open" -> {
                        broadcast(intent(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION))
                        result.success(null)
                    }
                    "close" -> {
                        broadcast(intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION))
                        result.success(null)
                    }
                    "panel" -> try {
                        startActivityForResult(
                            intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL), 0)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun releaseVisualizer() {
        visualizer?.release()
        visualizer = null
    }

    override fun onDestroy() {
        releaseVisualizer()
        super.onDestroy()
    }

    private fun broadcast(intent: Intent) {
        sendBroadcast(intent)
        // Android 8+ does not deliver implicit broadcasts to receivers declared
        // in a manifest, which is how equalizer apps listen, so send it to each
        // of them directly as well (they are listed in <queries>).
        for (r in packageManager.queryBroadcastReceivers(intent, 0)) {
            sendBroadcast(Intent(intent).setClassName(r.activityInfo.packageName, r.activityInfo.name))
        }
    }
}
