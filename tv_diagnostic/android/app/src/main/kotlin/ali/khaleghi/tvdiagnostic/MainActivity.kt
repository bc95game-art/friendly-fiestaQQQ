package ali.khaleghi.tvdiagnostic

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * نسخه ۱.۲ — با ضبط کامل و پایدار
 *
 * بهبودها نسبت به نسخه قبل:
 * ۱. override صریح onKeyDown و onKeyUp برای دریافت کلیدهایی که ممکن است
 *    dispatchKeyEvent از دستشان بدهد (مثلاً BACK در برخی ROM‌ها)
 * ۲. dispatchKeyEvent همچنان نگه داشته شده برای اطمینان از دریافت همه کلیدها
 * ۳. ارسال اطلاعات کامل‌تر: IR scanCode دقیق + نام دستگاه ورودی
 * ۴. جلوگیری از ارسال رویدادهای تکراری (repeatCount > 0) در کانال
 */
class MainActivity : FlutterActivity() {

    private val keyChannelName = "daewoo_tv_diag/keys"
    private val btChannelName  = "daewoo_tv_diag/bt"

    private var keySink: EventChannel.EventSink? = null
    private var btSink:  EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val timeFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    // برای جلوگیری از ارسال رویداد تکراری از dispatchKeyEvent و onKeyDown
    private val sentKeys = LinkedHashMap<String, Long>(64, 0.75f, true)
    private val dedupeWindowMs = 30L

    // ── گیرنده رویداد بلوتوث ──────────────────────────────────────────────
    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device: BluetoothDevice? =
                if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                else
                    @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

            val name = try { device?.name ?: device?.address ?: "?" }
                       catch (e: SecurityException) { device?.address ?: "?" }

            val msg = when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED    -> "CONNECTED|$name"
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> "DISCONNECTED|$name"
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)
                    val stateName = when (state) {
                        BluetoothDevice.BOND_BONDED  -> "BONDED"
                        BluetoothDevice.BOND_BONDING -> "BONDING"
                        BluetoothDevice.BOND_NONE    -> "NONE"
                        else -> "UNKNOWN($state)"
                    }
                    "BOND|$name|$stateName"
                }
                else -> return
            }
            val time = timeFmt.format(Date())
            emit(btSink, "$time|$msg")
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
        try { unregisterReceiver(btReceiver) } catch (_: IllegalArgumentException) {}
        super.onDestroy()
    }

    // ── ضبط همه KeyEvent‌ها از dispatchKeyEvent ─────────────────────────
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // فقط رویداد DOWN را ضبط می‌کنیم (بدون تکرار)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            sendKeyEvent(event, "DOWN")
        } else if (event.action == KeyEvent.ACTION_UP) {
            sendKeyEvent(event, "UP")
        }
        return super.dispatchKeyEvent(event)
    }

    // ── override صریح onKeyDown برای دریافت کلیدهای خاص ─────────────────
    // بعضی کلیدها مثل BACK در برخی ROM‌ها ممکن است قبل از dispatchKeyEvent
    // توسط Flutter مصرف شوند — این override مستقیماً از لایه اندروید گرفته
    // می‌شود و مطمئن‌تر است.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (event.repeatCount == 0) {
            // اگر dispatchKeyEvent این رویداد را قبلاً فرستاده باشد، skip
            if (!wasRecentlySent(event, "DOWN")) {
                sendKeyEvent(event, "DOWN")
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (!wasRecentlySent(event, "UP")) {
            sendKeyEvent(event, "UP")
        }
        return super.onKeyUp(keyCode, event)
    }

    // ── بررسی ارسال تکراری (کمتر از ۳۰ میلی‌ثانیه) ─────────────────────
    private fun wasRecentlySent(event: KeyEvent, action: String): Boolean {
        val key = "${action}:${event.keyCode}:${event.scanCode}:${event.deviceId}"
        val now = System.currentTimeMillis()
        val lastSent = sentKeys[key] ?: 0L
        return (now - lastSent) < dedupeWindowMs
    }

    // ── ساخت و ارسال پیام رویداد کلید ───────────────────────────────────
    private fun sendKeyEvent(event: KeyEvent, action: String) {
        val keyCode  = event.keyCode
        val keyName  = KeyEvent.keyCodeToString(keyCode)
        val scanCode = event.scanCode
        val source   = event.source
        val repeat   = event.repeatCount
        val deviceId = event.deviceId

        val inputDev = event.device
        val devName  = inputDev?.name?.replace("|", "/") ?: "?"

        // تشخیص نوع منبع
        val srcParts = mutableListOf<String>()
        if (source and InputDevice.SOURCE_KEYBOARD  != 0) srcParts.add("KB")
        if (source and InputDevice.SOURCE_GAMEPAD   != 0) srcParts.add("GP")
        if (source and InputDevice.SOURCE_DPAD      != 0) srcParts.add("DP")
        if (source and InputDevice.SOURCE_JOYSTICK  != 0) srcParts.add("JOY")
        if (source and InputDevice.SOURCE_HDMI      != 0) srcParts.add("HDMI")
        val srcStr = if (srcParts.isEmpty()) "0x${Integer.toHexString(source)}" else srcParts.joinToString("+")

        val time = timeFmt.format(Date())

        // ثبت در جدول ارسال‌شده‌ها برای جلوگیری از تکرار
        val dedupeKey = "${action}:${keyCode}:${scanCode}:${deviceId}"
        sentKeys[dedupeKey] = System.currentTimeMillis()
        // نگه داشتن فقط ۱۰۰ آیتم آخر
        if (sentKeys.size > 100) {
            val oldestKey = sentKeys.entries.first().key
            sentKeys.remove(oldestKey)
        }

        // فرمت pipe-separated:
        // time|action|keyCode|keyName|scanCode|source|deviceId|deviceName|repeat
        val msg = "$time|$action|$keyCode|$keyName|$scanCode|$srcStr|$deviceId|$devName|$repeat"
        emit(keySink, msg)
    }

    private fun emit(sink: EventChannel.EventSink?, msg: String) {
        mainHandler.post { sink?.success(msg) }
    }
}
