package de.rixk.specular

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Share target (SPEC.md §3.2): appears as "Specular" in the system Share
 * menu. Runs the lightweight `shareMain` Dart entrypoint in a transparent
 * window, shows "Sent" and closes again. The main app UI never opens.
 */
class ShareActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getShared" -> result.success(sharedPayload(intent))
                    "finish" -> {
                        result.success(null)
                        finishWithoutAnimation()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sharedPayload(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        // Some apps put a CharSequence (with spans) instead of a String.
        return mapOf(
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "subject" to intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString(),
        )
    }

    private fun finishWithoutAnimation() {
        finish()
        if (Build.VERSION.SDK_INT >= 34) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    private companion object {
        const val CHANNEL = "de.rixk.specular/share"
    }
}
