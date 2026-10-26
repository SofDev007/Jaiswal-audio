package com.jaiswal.jarx

import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.audiofx.AudioEffect
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Offers JARX's audio session to equalizer apps, takes it back, or opens
    // the installed equalizer's panel. PlayerEngine decides when.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
