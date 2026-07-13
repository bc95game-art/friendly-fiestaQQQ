package ali.khaleghi.tvdiagnostic

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * پل بین Dart و دو منبع واقعی اطلاعات سخت‌افزاری تلویزیون:
 *
 * ۱) "daewoo_tv_diag/keys" — هر KeyEvent واقعی که اندروید به این اکتیویتی
 *    می‌دهد (چه از گیرنده‌ی مادون‌قرمز خودِ تلویزیون بیاید، چه از یک
 *    ریموت/گوشیِ متصل با HID بلوتوثی) — دقیقاً همانی که خودِ سیستم‌عامل
 *    دریافت کرده، بدون هیچ حدس یا واسطه.
 *
 * ۲) "daewoo_tv_diag/bt" — رویدادهای اتصال/جفت‌شدن بلوتوث در سطح سیستم
 *    (ACL_CONNECTED / ACL_DISCONNECTED / BOND_STATE_CHANGED) — تا معلوم شود
 *    آیا اتصال اصلاً در لایه‌ی اندروید برقرار می‌شود یا نه، مستقل از چیزی
 *    که اپ گوشی ادعا می‌کند.
 */
class MainActivity : FlutterActivity() {
    private val keyChannelName = "daewoo_tv_diag/keys"
    private val btChannelName = "daewoo_tv_diag/bt"

    private var keySink: EventChannel.EventSink? = null
    private var btSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val timeFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device: BluetoothDevice? =
                if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                else
                    @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

            val name = try { device?.name ?: device?.address ?: "?" } catch (e: SecurityException) { "?" }

            val msg = when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> "🔗 ACL_CONNECTED از $name"
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> "❌ ACL_DISCONNECTED از $name"
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)
                    val stateName = when (state) {
                        BluetoothDevice.BOND_BONDED -> "BONDED (جفت‌شده)"
                        BluetoothDevice.BOND_BONDING -> "BONDING (در حال جفت‌شدن)"
                        BluetoothDevice.BOND_NONE -> "BOND_NONE (جفت نیست)"
                        else -> "نامشخص($state)"
                    }
                    "🔄 BOND_STATE_CHANGED با $name → $stateName"
                }
                else -> return
            }
            emit(btSink, "[${timeFmt.format(Date())}] $msg")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, keyChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) { keySink = sink }
                override fun onCancel(args: Any?) { keySink = null }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, btChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) { btSink = sink }
                override fun onCancel(args: Any?) { btSink = null }
            })

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(btReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(btReceiver, filter)
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(btReceiver) } catch (e: IllegalArgumentException) { /* ثبت نشده بود */ }
        super.onDestroy()
    }

    private fun emit(sink: EventChannel.EventSink?, msg: String) {
        mainHandler.post { sink?.success(msg) }
    }

    // ⚠️ نکته‌ی اصلی: این متد، تنها منبع «حقیقتِ» واقعی است — هر کلیدی که
    // اینجا نرسد یعنی اصلاً به لایه‌ی اندروید هم نرسیده (نه فقط این اپ).
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val actionName = when (event.action) {
            KeyEvent.ACTION_DOWN -> "DOWN"
            KeyEvent.ACTION_UP -> "UP"
            else -> "?"
        }
        val keyName = KeyEvent.keyCodeToString(event.keyCode)
        val src = event.source
        emit(
            keySink,
            "[${timeFmt.format(Date())}] $actionName  keyCode=${event.keyCode} ($keyName)  " +
                "scanCode=${event.scanCode}  source=0x${Integer.toHexString(src)}  repeat=${event.repeatCount}",
        )
        return super.dispatchKeyEvent(event)
    }
}
