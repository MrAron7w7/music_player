package com.example.music_app

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var dartReady = false
    private var pendingAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dartReady = false
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simple_music/widget"
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    pendingAction?.let { action ->
                        pendingAction = null
                        channel?.invokeMethod("onAction", action)
                    }
                    result.success(null)
                }
                "update" -> {
                    updateWidget(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "clear" -> {
                    clearWidget()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        val received = intent ?: return
        val action = received.getStringExtra(MusicWidgetProvider.EXTRA_ACTION) ?: return
        received.removeExtra(MusicWidgetProvider.EXTRA_ACTION)
        if (dartReady) {
            channel?.invokeMethod("onAction", action)
        } else {
            pendingAction = action
        }
    }

    private fun updateWidget(arguments: Map<*, *>?) {
        if (arguments == null) return
        val prefs = getSharedPreferences(MusicWidgetProvider.PREFS, MODE_PRIVATE)
        val editor = prefs.edit()
        editor.putString("title", arguments["title"] as? String ?: "Simple Music")
        editor.putString("artist", arguments["artist"] as? String ?: "")
        editor.putBoolean("playing", arguments["playing"] as? Boolean ?: false)

        val artwork = arguments["artwork"] as? ByteArray
        if (artwork != null && artwork.isNotEmpty()) {
            try {
                val file = File(filesDir, "widget_artwork.img")
                FileOutputStream(file).use { it.write(artwork) }
                editor.putString("artwork_path", file.absolutePath)
            } catch (_: Exception) {
                editor.remove("artwork_path")
            }
        } else {
            editor.remove("artwork_path")
            try {
                File(filesDir, "widget_artwork.img").delete()
            } catch (_: Exception) {
            }
        }
        editor.apply()
        MusicWidgetProvider.updateAll(applicationContext)
    }

    private fun clearWidget() {
        val prefs = getSharedPreferences(MusicWidgetProvider.PREFS, MODE_PRIVATE)
        prefs.edit().clear().apply()
        try {
            File(filesDir, "widget_artwork.img").delete()
        } catch (_: Exception) {
        }
        MusicWidgetProvider.updateAll(applicationContext)
    }
}
