package ali.khaleghi.daewooremote

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * پل واقعی بین Dart و ConsumerIrManager اندروید.
 * این API فقط روی گوشی‌هایی که سخت‌افزار فرستنده IR دارند کار می‌کند
 * (hasIrEmitter آن را چک می‌کند).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "daewoo/ir"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val irManager = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasIrEmitter" -> {
                        result.success(irManager?.hasIrEmitter() ?: false)
                    }
                    "transmit" -> {
                        if (irManager == null || !irManager.hasIrEmitter()) {
                            result.error("no_ir_emitter", "این گوشی فرستنده IR ندارد", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val frequency = (call.argument<Int>("frequency")) ?: 38000
                            @Suppress("UNCHECKED_CAST")
                            val patternList = call.argument<List<Int>>("pattern")
                                ?: emptyList<Int>()
                            val pattern = patternList.toIntArray()

                            irManager.transmit(frequency, pattern)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("transmit_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
