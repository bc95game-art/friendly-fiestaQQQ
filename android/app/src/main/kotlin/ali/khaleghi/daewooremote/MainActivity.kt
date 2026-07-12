package ali.khaleghi.daewooremote

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.hardware.ConsumerIrManager
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * پل واقعی بین Dart و دو قابلیت سخت‌افزاری:
 *
 * ۱) "daewoo/ir" — ConsumerIrManager (فرستنده IR واقعی گوشی) — بدون تغییر.
 *
 * ۲) "daewoo/bt_hid" — پروفایل استاندارد اندروید BluetoothHidDevice.
 *    گوشی خودش را نزد سیستم به‌عنوان یک دستگاه ورودی بلوتوثی (کیبورد +
 *    کنترل چندرسانه‌ای + موس) معرفی می‌کند و مستقیماً به تلویزیون (که باید
 *    از قبل با گوشی Pair شده باشد) متصل می‌شود. این جایگزین واقعی و
 *    کارکردی روش قبلی (BLE GATT با UUID ساختگی) است — نیازمند اندروید ۹
 *    (API 28) به بالا.
 */
class MainActivity : FlutterActivity() {
    private val irChannelName = "daewoo/ir"
    private val hidChannelName = "daewoo/bt_hid"
    private val hidEventChannelName = "daewoo/bt_hid/state"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val directExecutor = Executor { command -> mainHandler.post(command) }

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDevice: BluetoothHidDevice? = null
    private var connectedDevice: BluetoothDevice? = null
    private var registered = false
    private var hidEventSink: EventChannel.EventSink? = null

    companion object {
        private const val REPORT_ID_KEYBOARD: Byte = 1
        private const val REPORT_ID_CONSUMER: Byte = 2
        private const val REPORT_ID_MOUSE: Byte = 3
        private const val RELEASE_DELAY_MS = 45L

        // توصیفگر HID استاندارد: کیبورد (Report ID 1) + کنترل چندرسانه‌ای
        // ۱۶‌بیتی (Report ID 2) + موس نسبی سه‌دکمه (Report ID 3).
        private val HID_DESCRIPTOR: ByteArray = byteArrayOf(
            // ── Keyboard (Report ID 1) ──────────────────────────────
            0x05, 0x01,             // Usage Page (Generic Desktop)
            0x09, 0x06,             // Usage (Keyboard)
            0xA1.toByte(), 0x01,    // Collection (Application)
            0x85.toByte(), REPORT_ID_KEYBOARD,
            0x05, 0x07,             // Usage Page (Key Codes)
            0x19, 0xE0.toByte(),
            0x29, 0xE7.toByte(),
            0x15, 0x00,
            0x25, 0x01,
            0x75, 0x01,
            0x95.toByte(), 0x08.toByte(),
            0x81.toByte(), 0x02,    // Input (modifier byte)
            0x95.toByte(), 0x01,
            0x75, 0x08.toByte(),
            0x81.toByte(), 0x01,    // Input (reserved byte)
            0x95.toByte(), 0x06,
            0x75, 0x08.toByte(),
            0x15, 0x00,
            0x25, 0x65,
            0x05, 0x07,
            0x19, 0x00,
            0x29, 0x65,
            0x81.toByte(), 0x00,    // Input (6 keycodes)
            0xC0.toByte(),          // End Collection

            // ── Consumer Control (Report ID 2) ───────────────────────
            0x05, 0x0C,             // Usage Page (Consumer)
            0x09, 0x01,             // Usage (Consumer Control)
            0xA1.toByte(), 0x01,    // Collection (Application)
            0x85.toByte(), REPORT_ID_CONSUMER,
            0x15, 0x00,
            0x26, 0xFF.toByte(), 0x03,   // Logical Maximum (1023)
            0x19, 0x00,
            0x2A, 0xFF.toByte(), 0x03,   // Usage Maximum (1023)
            0x75, 0x10,             // Report Size (16)
            0x95.toByte(), 0x01,
            0x81.toByte(), 0x00,    // Input (Data, Array)
            0xC0.toByte(),          // End Collection

            // ── Mouse (Report ID 3) ──────────────────────────────────
            0x05, 0x01,             // Usage Page (Generic Desktop)
            0x09, 0x02,             // Usage (Mouse)
            0xA1.toByte(), 0x01,    // Collection (Application)
            0x09, 0x01,             // Usage (Pointer)
            0xA1.toByte(), 0x00,    // Collection (Physical)
            0x85.toByte(), REPORT_ID_MOUSE,
            0x05, 0x09,             // Usage Page (Buttons)
            0x19, 0x01,
            0x29, 0x03,
            0x15, 0x00,
            0x25, 0x01,
            0x95.toByte(), 0x03,
            0x75, 0x01,
            0x81.toByte(), 0x02,    // Input (3 button bits)
            0x95.toByte(), 0x01,
            0x75, 0x05,
            0x81.toByte(), 0x01,    // Input (padding)
            0x05, 0x01,
            0x09, 0x30,             // Usage (X)
            0x09, 0x31,             // Usage (Y)
            0x15, 0x81.toByte(),    // Logical Minimum (-127)
            0x25, 0x7F,             // Logical Maximum (127)
            0x75, 0x08.toByte(),
            0x95.toByte(), 0x02,
            0x81.toByte(), 0x06,    // Input (Data, Variable, Relative)
            0xC0.toByte(),          // End Collection
            0xC0.toByte()           // End Collection
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupIrChannel(flutterEngine)
        setupHidChannel(flutterEngine)
    }

    // ═════════════════════════ IR (بدون تغییر) ═════════════════════════
    private fun setupIrChannel(flutterEngine: FlutterEngine) {
        val irManager = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, irChannelName)
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

    // ═══════════════════════ Bluetooth HID Device ══════════════════════
    private fun setupHidChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, hidEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    hidEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    hidEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hidChannelName)
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    // ⚠️ رفع باگ: قبلاً همه‌ی متدها (نه فقط register) وقتی نسخه‌ی
                    // اندروید قدیمی بود success(false) برمی‌گرداندند و سمت Dart
                    // این را با هر «false» دیگری (مثل بلوتوث خاموش) یکسان می‌دید،
                    // پس پیام غلط «نسخه اندروید شما پشتیبانی نمی‌شود» حتی برای
                    // گوشی‌های جدید نشان داده می‌شد. حالا فقط وقتی که واقعاً
                    // SDK پایین‌تر از ۲۸ است این کد خطای مشخص برگردانده می‌شود.
                    if (call.method == "register") {
                        result.error("sdk_unsupported",
                            "این نسخه‌ی اندروید (کمتر از ۹) از حالت کنترل بلوتوثی پشتیبانی نمی‌کند", null)
                    } else {
                        result.success(false)
                    }
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "register" -> registerHid(result)
                    "bondedDevices" -> {
                        if (!hasConnectPermission()) {
                            result.error("permission_denied",
                                "مجوز BLUETOOTH_CONNECT هنوز به این اپ داده نشده", null)
                        } else {
                            result.success(bondedDevicesList())
                        }
                    }
                    "connect" -> {
                        if (!hasConnectPermission()) {
                            result.error("permission_denied",
                                "مجوز BLUETOOTH_CONNECT هنوز به این اپ داده نشده", null)
                            return@setMethodCallHandler
                        }
                        val address = call.argument<String>("address")
                        connectTo(address, result)
                    }
                    "disconnect" -> {
                        disconnectCurrent()
                        result.success(true)
                    }
                    "requestDiscoverable" -> requestDiscoverable(result)
                    "localName" -> result.success(adapter()?.name)
                    "sendConsumer" -> {
                        val usage = call.argument<Int>("usage") ?: 0
                        result.success(sendConsumerUsage(usage))
                    }
                    "sendKeyboard" -> {
                        val usage = call.argument<Int>("usage") ?: 0
                        result.success(sendKeyboardUsage(usage))
                    }
                    "sendMouseMove" -> {
                        val dx = call.argument<Int>("dx") ?: 0
                        val dy = call.argument<Int>("dy") ?: 0
                        result.success(sendMouseReport(0, dx, dy))
                    }
                    "sendMouseClick" -> {
                        result.success(sendMouseClick())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun adapter(): BluetoothAdapter? {
        if (bluetoothAdapter == null) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = manager?.adapter
        }
        return bluetoothAdapter
    }

    /// بررسی واقعی و مستقیم (نه فقط چیزی که سمت Dart فکر می‌کند) اینکه آیا
    /// مجوز BLUETOOTH_CONNECT همین الان از نگاه سیستم‌عامل داده شده یا نه.
    ///
    /// چرا این بررسی جداگانه لازم است؟ باگ گزارش‌شده («وصل شده ولی
    /// می‌گفت دستگاهی یافت نشد») ناشی از این بود که adapter.bondedDevices
    /// یک SecurityException پرتاب می‌کرد (چون مجوز واقعاً گرفته نشده بود)
    /// و آن استثنا بی‌سروصدا به لیست خالی تبدیل می‌شد — یعنی کاربر پیام
    /// گمراه‌کننده‌ی «دستگاهی یافت نشد» می‌دید، درحالی‌که مشکل واقعی نبود
    /// مجوز بود، نه نبود دستگاه Pair‌شده. حالا این دو حالت را از هم جدا
    /// می‌کنیم تا پیام درست به کاربر نشان داده شود.
    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.BLUETOOTH_CONNECT
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun registerHid(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            // ⚠️ رفع باگ: قبلاً این حالت هم success(false) برمی‌گرداند و با
            // «نسخه اندروید قدیمی» اشتباه گرفته می‌شد. این گوشی اصلاً سخت‌افزار
            // بلوتوث ندارد — نادر، ولی پیام باید دقیق باشد.
            result.error("no_bluetooth_hardware", "این گوشی سخت‌افزار بلوتوث ندارد", null)
            return
        }
        if (!adapter.isEnabled) {
            // ⚠️ رفع باگ اصلی گزارش‌شده: علت واقعی پیام غلط «نسخه اندروید شما
            // پشتیبانی نمی‌کند». وقتی بلوتوث گوشی خاموش است، این کد قبلاً
            // success(false) برمی‌گرداند و سمت Dart آن را دقیقاً مثل «این
            // گوشی هیچ‌وقت نمی‌تواند حالت بلوتوثی را اجرا کند» تفسیر می‌کرد —
            // درحالی‌که مشکل فقط این بود که بلوتوث خاموش بود، نه نسخه‌ی
            // اندروید. حالا این دو حالت را کاملاً جدا می‌کنیم.
            result.error("bluetooth_disabled", "بلوتوث گوشی خاموش است — آن را روشن کنید", null)
            return
        }
        if (registered && hidDevice != null) {
            result.success(true)
            return
        }

        val sdp = BluetoothHidDeviceAppSdpSettings(
            "کنترل هوشمند دوو",
            "ریموت بلوتوثی مجازی",
            "ali.khaleghi.daewooremote",
            BluetoothHidDevice.SUBCLASS1_COMBO,
            HID_DESCRIPTOR
        )
        val qos = BluetoothHidDeviceAppQosSettings(
            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
            800, 9, 0, 640, 9600
        )

        adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                hidDevice = proxy as BluetoothHidDevice
                val ok = hidDevice?.registerApp(
                    sdp, qos, qos, directExecutor,
                    object : BluetoothHidDevice.Callback() {
                        override fun onAppStatusChanged(
                            pluggedDevice: BluetoothDevice?,
                            registeredNow: Boolean
                        ) {
                            registered = registeredNow
                        }

                        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
                            when (state) {
                                BluetoothProfile.STATE_CONNECTED -> {
                                    connectedDevice = device
                                    hidEventSink?.success("connected")
                                }
                                BluetoothProfile.STATE_CONNECTING -> {
                                    hidEventSink?.success("connecting")
                                }
                                BluetoothProfile.STATE_DISCONNECTED,
                                BluetoothProfile.STATE_DISCONNECTING -> {
                                    if (connectedDevice?.address == device?.address) {
                                        connectedDevice = null
                                    }
                                    hidEventSink?.success("disconnected")
                                }
                            }
                        }
                    }
                ) ?: false
                if (ok) {
                    result.success(true)
                } else {
                    result.error("register_failed", "ثبت پروفایل HID بلوتوث ناموفق بود", null)
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                registered = false
                hidDevice = null
                connectedDevice = null
                hidEventSink?.success("disconnected")
            }
        }, BluetoothProfile.HID_DEVICE)
    }

    /// درخواست «قابل مشاهده» شدن گوشی برای ۱۲۰ ثانیه.
    ///
    /// چرا لازم است؟ روی برخی تلویزیون‌های اندرویدی (به‌خصوص باکس‌های
    /// سفید-برچسب مثل این مدل که Bluetooth stack سازنده‌اش شبیه دستگاه‌های
    /// غیر-اندرویدی (کامپیوتر/PC) رفتار می‌کند)، شروع اتصال HID از سمت
    /// گوشی (hid.connect) همیشه قابل اعتماد نیست — طبق مستندات و تجربه‌ی
    /// توسعه‌دهندگان دیگر با همین API (BluetoothHidDevice)، برخی
    /// میزبان‌ها (host) فقط زمانی اتصال HID را می‌پذیرند که خودشان اتصال
    /// را آغاز کنند، نه دستگاه ورودی (گوشی). راه‌حل واقعی: گوشی را قابل
    /// مشاهده می‌کنیم تا از روی خودِ تلویزیون (تنظیمات ← بلوتوث ← افزودن
    /// دستگاه) به آن وصل شود.
    private fun requestDiscoverable(result: MethodChannel.Result) {
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun bondedDevicesList(): List<Map<String, String>> {
        val adapter = adapter() ?: return emptyList()
        return try {
            adapter.bondedDevices.map { d ->
                mapOf("name" to (d.name ?: ""), "address" to d.address)
            }
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    private fun connectTo(address: String?, result: MethodChannel.Result) {
        val adapter = adapter()
        val device = adapter?.bondedDevices?.firstOrNull { it.address == address }
        val hid = hidDevice
        if (address == null || device == null || hid == null) {
            result.success(false)
            return
        }
        try {
            result.success(hid.connect(device))
        } catch (e: SecurityException) {
            result.success(false)
        }
    }

    private fun disconnectCurrent() {
        val device = connectedDevice ?: return
        try {
            hidDevice?.disconnect(device)
        } catch (e: SecurityException) {
            // نادیده گرفته می‌شود
        }
        connectedDevice = null
    }

    private fun sendConsumerUsage(usage: Int): Boolean {
        val device = connectedDevice ?: return false
        val hid = hidDevice ?: return false
        val press = byteArrayOf((usage and 0xFF).toByte(), ((usage shr 8) and 0xFF).toByte())
        val ok = try {
            hid.sendReport(device, REPORT_ID_CONSUMER.toInt(), press)
        } catch (e: SecurityException) {
            false
        }
        mainHandler.postDelayed({
            try {
                hid.sendReport(device, REPORT_ID_CONSUMER.toInt(), byteArrayOf(0, 0))
            } catch (e: SecurityException) {
                // نادیده گرفته می‌شود
            }
        }, RELEASE_DELAY_MS)
        return ok
    }

    private fun sendKeyboardUsage(usage: Int): Boolean {
        val device = connectedDevice ?: return false
        val hid = hidDevice ?: return false
        val press = byteArrayOf(0, 0, usage.toByte(), 0, 0, 0, 0, 0)
        val ok = try {
            hid.sendReport(device, REPORT_ID_KEYBOARD.toInt(), press)
        } catch (e: SecurityException) {
            false
        }
        mainHandler.postDelayed({
            try {
                hid.sendReport(device, REPORT_ID_KEYBOARD.toInt(), ByteArray(8))
            } catch (e: SecurityException) {
                // نادیده گرفته می‌شود
            }
        }, RELEASE_DELAY_MS)
        return ok
    }

    private fun sendMouseReport(buttons: Int, dx: Int, dy: Int): Boolean {
        val device = connectedDevice ?: return false
        val hid = hidDevice ?: return false
        val clampedDx = dx.coerceIn(-127, 127)
        val clampedDy = dy.coerceIn(-127, 127)
        val report = byteArrayOf(buttons.toByte(), clampedDx.toByte(), clampedDy.toByte())
        return try {
            hid.sendReport(device, REPORT_ID_MOUSE.toInt(), report)
        } catch (e: SecurityException) {
            false
        }
    }

    private fun sendMouseClick(): Boolean {
        val down = sendMouseReport(1, 0, 0)
        mainHandler.postDelayed({ sendMouseReport(0, 0, 0) }, RELEASE_DELAY_MS)
        return down
    }
}
