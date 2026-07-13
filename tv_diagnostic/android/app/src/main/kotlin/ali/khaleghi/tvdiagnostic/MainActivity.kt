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
 * نسخه ارتقاء‌یافته — هدف: کشیدن نگاشت واقعی HID از تلویزیون.
 *
 * هر KeyEvent را به‌صورت JSON ساختار‌یافته می‌فرستد تا Dart بتواند آن را
 * parse کرده و جدول نگاشت زنده بسازد:
 *   keyCode   → کد اندروید (مثلاً ۲۶۴ = KEYCODE_VOLUME_UP)
 *   keyName   → اسم رسمی اندروید (مثلاً "KEYCODE_VOLUME_UP")
 *   scanCode  → کد خام لینوکس/HID که از دستگاه ورودی آمده
 *   source    → منبع: SOURCE_KEYBOARD, SOURCE_GAMEPAD, ...
 *   deviceId  → شناسه InputDevice در اندروید
 *   deviceName→ اسم دستگاه ورودی (مثلاً "SM-G991B Keyboard")
 *   action    → "DOWN" یا "UP"
 *   repeat    → تعداد تکرار (۰ = اولین فشار)
 *   time      → ساعت:دقیقه:ثانیه.میلی‌ثانیه
 */
class MainActivity : FlutterActivity() {

    private val keyChannelName = "daewoo_tv_diag/keys"
    private val btChannelName  = "daewoo_tv_diag/bt"

    private var keySink: EventChannel.EventSink? = null
    private var btSink:  EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val timeFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

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

    // ── راه‌اندازی کانال‌ها ────────────────────────────────────────────────
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

    // ── ضبط هر KeyEvent واقعی ────────────────────────────────────────────
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val action = when (event.action) {
            KeyEvent.ACTION_DOWN -> "DOWN"
            KeyEvent.ACTION_UP   -> "UP"
            else -> "OTHER"
        }

        val keyCode  = event.keyCode
        val keyName  = KeyEvent.keyCodeToString(keyCode)
        val scanCode = event.scanCode
        val source   = event.source
        val repeat   = event.repeatCount
        val deviceId = event.deviceId

        // نام و نوع دستگاه ورودی
        val inputDev  = event.device
        val devName   = inputDev?.name?.replace("|", "/") ?: "?"

        // تشخیص نوع منبع
        val srcParts = mutableListOf<String>()
        if (source and InputDevice.SOURCE_KEYBOARD  != 0) srcParts.add("KB")
        if (source and InputDevice.SOURCE_GAMEPAD   != 0) srcParts.add("GP")
        if (source and InputDevice.SOURCE_DPAD      != 0) srcParts.add("DP")
        if (source and InputDevice.SOURCE_JOYSTICK  != 0) srcParts.add("JOY")
        if (source and InputDevice.SOURCE_HDMI      != 0) srcParts.add("HDMI")
        val srcStr = if (srcParts.isEmpty()) "0x${Integer.toHexString(source)}" else srcParts.joinToString("+")

        val time = timeFmt.format(Date())

        // فرمت pipe-separated — سبک، بدون نیاز به JSON parser در Dart
        // time|action|keyCode|keyName|scanCode|source|deviceId|deviceName|repeat
        val msg = "$time|$action|$keyCode|$keyName|$scanCode|$srcStr|$deviceId|$devName|$repeat"
        emit(keySink, msg)

        return super.dispatchKeyEvent(event)
    }

    private fun emit(sink: EventChannel.EventSink?, msg: String) {
        mainHandler.post { sink?.success(msg) }
    }
}
