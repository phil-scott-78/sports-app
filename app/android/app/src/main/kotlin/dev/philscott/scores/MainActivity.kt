package dev.philscott.scores

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Hosts the `scores/recap` channel: the ON-DEVICE AI inning recap (Gemini Nano
 * via the ML Kit GenAI Prompt API). Policy: use the model only when it is
 * already AVAILABLE on the device — this app never triggers a model download
 * (DOWNLOADABLE reads as "not available"; the Dart side falls back to the
 * deterministic recap line). Every failure answers null/false, never an error.
 */
class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var model: GenerativeModel? = null

    private fun client(): GenerativeModel =
        model ?: Generation.getClient().also { model = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scores/recap")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> scope.launch {
                        result.success(
                            try {
                                client().checkStatus() == FeatureStatus.AVAILABLE
                            } catch (e: Exception) {
                                false
                            }
                        )
                    }
                    "summarize" -> {
                        val prompt = call.argument<String>("prompt")
                        if (prompt.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            result.success(
                                try {
                                    if (client().checkStatus() == FeatureStatus.AVAILABLE) {
                                        client().generateContent(prompt)
                                            .candidates.firstOrNull()?.text
                                    } else {
                                        null
                                    }
                                } catch (e: Exception) {
                                    null
                                }
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        model?.close()
        scope.cancel()
        super.onDestroy()
    }
}
