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
    // ⚠️ رفع باگ mouse-click race: اگر کاربر سریع کلیک کند، postDelayed قبلی
    // هنوز در صف است و وقتی فایر می‌شود button را آزاد می‌کند در حالی که
    // کلیک جدید در حال ارسال است. این Runnable مرجع آزادسازی معلق را نگه
    // می‌دارد تا قبل از هر کلیک جدید کنسل شود.
    private var pendingMouseRelease: Runnable? = null

    // ⚠️ رفع باگ «اتصال بعد از رفتن و برگشت به صفحه/بعد از قطع، تا ری‌استارت
    // کامل اپ برقرار نمی‌شود»: قبلاً هر بار Dart سمت initState دوباره
    // getProfileProxy را صدا می‌زد در حالی که ممکن بود یک ثبت قبلی هنوز
    // «در حال انجام» باشد — این باعث پروکسی‌های موازی/ناسازگار می‌شد که
    // اندروید بعد از آن دیگر اتصال HID را قبول نمی‌کرد مگر با ری‌استارت
    // کامل پروسه (که hidDevice/registered را از صفر می‌ساخت). این پرچم
    // از هم‌پوشانی درخواست‌های ثبت جلوگیری می‌کند.
    private var registering = false

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

    // نکته: نصبِ گیرنده‌ی سراسری کرش (CrashLogger.install) به DaewooApplication
    // منتقل شد — چون Application.onCreate زودتر از MainActivity.onCreate اجرا
    // می‌شود و پس زودترین لحظه‌ی ممکن برای گرفتن هر کرش احتمالی است.

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
                    "reset" -> hardReset(result)
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
                    // ⚠️ بدون دسترسی کاربر به logcat/Play Console، تنها راه واقعی
                    // فهمیدن علت دقیق کرش این است که خودِ اپ آن را ذخیره کند.
                    // این متد آخرین کرش ثبت‌شده توسط CrashLogger (نوشته‌شده در
                    // Application.onCreate، قبل از هر چیز دیگر) را می‌خواند و
                    // بعد از خواندن پاک می‌کند تا فقط یک‌بار نمایش داده شود.
                    "lastCrashLog" -> result.success(CrashLogger.readAndClear(applicationContext))
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
        if (registering) {
            // یک ثبت قبلاً در حال انجام است — دوباره getProfileProxy صدا
            // نمی‌زنیم (رفع باگ پروکسی‌های موازی)
            result.success(true)
            return
        }
        registering = true

        // ⚠️ رفع باگ «قفل‌شدن اپ»: اگر BT service هرگز onServiceConnected نفرستد
        // (کرش سرویس، ROM سفارشی، یا race هنگام خاموش/روشن‌شدن بلوتوث)،
        // registering=true می‌ماند و _busy در سمت Dart هم قفل می‌ماند —
        // اپ دیگر هیچ‌وقت نمی‌تواند اتصال بگیرد تا کاربر کاملاً آن را
        // ببندد و باز کند. timeout بعد از ۸ ثانیه state را پاک می‌کند.
        val timeoutRunnable = Runnable {
            if (registering) {
                registering = false
                try {
                    result.error("register_timeout",
                        "سرویس بلوتوث در زمان مقرر پاسخ نداد — بلوتوث را خاموش و روشن کنید", null)
                } catch (_: Throwable) {}
            }
        }
        mainHandler.postDelayed(timeoutRunnable, 8_000)

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
                mainHandler.removeCallbacks(timeoutRunnable)
                // ⚠️ رفع باگ crash: قبلاً «proxy as BluetoothHidDevice» (بدون ?)
                // استفاده می‌شد — اگر proxy از نوع اشتباه می‌بود ClassCastException
                // uncaught می‌انداخت و اپ crash می‌کرد. حالا از cast ایمن استفاده می‌شود.
                val hid = proxy as? BluetoothHidDevice
                if (hid == null) {
                    registering = false
                    result.error("register_failed", "پروفایل HID در دسترس نیست", null)
                    return
                }
                hidDevice = hid

                // ⚠️ رفع باگ crash اصلی: روی اندروید ۱۲+ (API 31+)، متد registerApp
                // در صورت نبودِ مجوز BLUETOOTH_CONNECT (یا هر مشکل سطح سیستم‌عامل)
                // یک SecurityException پرتاب می‌کند. این استثنا قبلاً اصلاً catch نمی‌شد
                // و چون در main thread بود، فوراً اپ را crash می‌کرد و می‌بست.
                // همچنین پرچم «registering» هرگز false نمی‌شد — یعنی بعد از crash و
                // باز کردن دوباره اپ (بدون ری‌استارت کامل) ثبت دیگر هرگز اتفاق
                // نمی‌افتاد. حالا هر دو مشکل رفع شده‌اند.
                val hidCallback = object : BluetoothHidDevice.Callback() {
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
                                // ⚠️ رفع باگ: برخی ROM‌ها هنگام disconnect، device=null
                                // می‌فرستند — در این حالت address قابل مقایسه نیست و
                                // connectedDevice هرگز null نمی‌شد (وضعیت state در
                                // سمت Kotlin «متصل» می‌ماند ولی واقعاً وصل نبود).
                                // حالا null device به‌معنی «همه‌ی اتصال‌ها قطع شدند» تفسیر می‌شود.
                                if (device == null || connectedDevice?.address == device.address) {
                                    connectedDevice = null
                                }
                                hidEventSink?.success("disconnected")
                            }
                        }
                    }
                }

                val ok: Boolean
                try {
                    ok = hid.registerApp(sdp, qos, qos, directExecutor, hidCallback) ?: false
                } catch (e: SecurityException) {
                    // مجوز BLUETOOTH_CONNECT در لحظه‌ی ثبت وجود نداشت
                    registering = false
                    result.error(
                        "permission_denied",
                        "مجوز بلوتوث برای ثبت HID لازم است — دوباره مجوز را اعطا کنید",
                        null
                    )
                    return
                } catch (e: Throwable) {
                    // ⚠️ رفع باگ کرش: قبلاً فقط Exception گرفته می‌شد. اما بعضی
                    // خطاهای واقعی این مسیر از نوع java.lang.Error هستند (مثل
                    // NoSuchMethodError/AbstractMethodError روی پشته‌ی بلوتوث
                    // برخی سازنده‌ها/ROMهای سفارشی، یا OutOfMemoryError لحظه‌ای)
                    // و Error زیرکلاس Exception نیست — با catch(Exception) قبلی
                    // اصلاً گرفته نمی‌شد و همچنان اپ را crash می‌کرد. Throwable
                    // که هم Exception و هم Error را می‌گیرد، تنها راه ایمن است.
                    registering = false
                    result.error(
                        "register_failed",
                        e.message ?: "خطای نامشخص در ثبت پروفایل HID",
                        null
                    )
                    return
                }

                registering = false
                if (ok) {
                    result.success(true)
                } else {
                    result.success(false)  // ok=false بدون استثنا → برگردان false به Dart
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                mainHandler.removeCallbacks(timeoutRunnable)
                registering = false
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
        } catch (e: Throwable) {
            emptyList()
        }
    }

    private fun connectTo(address: String?, result: MethodChannel.Result) {
        val adapter = adapter()
        // ⚠️ رفع باگ کرش: adapter?.bondedDevices روی اندروید ۱۲+ (API 31+) یا
        // برخی ROM‌های سفارشی می‌تواند SecurityException یا IllegalStateException
        // پرتاب کند حتی بعد از اعطای مجوز (race بین بررسی مجوز و فراخوانی).
        // چون این کد خارج از try-catch کانال متد Flutter اجرا می‌شود، هر
        // استثنای دستنگیرنشده مستقیماً به Android Looper می‌رسد و اپ را کرش
        // می‌کند. Exception (نه فقط SecurityException) برای پوشش همه حالات.
        val device = try {
            adapter?.bondedDevices?.firstOrNull { it.address == address }
        } catch (e: Throwable) {
            result.success(false)
            return
        }
        val hid = hidDevice
        if (address == null || device == null || hid == null) {
            result.success(false)
            return
        }
        // ⚠️ رفع باگ: قبلاً اگر یک اتصال قبلی ثبت بود، بلافاصله بعد از
        // disconnectCurrent() اتصال جدید می‌زدیم — پشته‌ی بلوتوث اندروید
        // disconnect را async پردازش می‌کند و اتصال جدید قبل از اتمام
        // disconnect رد می‌شود. رفع: اگر دستگاه قبلی متصل است، ۲۰۰ms صبر
        // می‌کنیم تا stack فرصت داشته باشد disconnect را کامل پردازش کند.
        if (connectedDevice != null) {
            disconnectCurrent()
            mainHandler.postDelayed({
                try {
                    result.success(hid.connect(device))
                } catch (e: Throwable) {
                    result.success(false)
                }
            }, 200)
            return
        }
        try {
            result.success(hid.connect(device))
        } catch (e: Throwable) {
            result.success(false)
        }
    }

    private fun disconnectCurrent() {
        val device = connectedDevice ?: return
        try {
            hidDevice?.disconnect(device)
        } catch (e: Throwable) {
            // نادیده گرفته می‌شود
        }
        connectedDevice = null
    }

    /// ریست کامل پروفایل HID: وقتی اتصال چند بار پشت‌سرهم شکست می‌خورد
    /// (نشانه‌ی گیر کردن پروکسی/ثبت قبلی در یک حالت ناسالم)، این متد
    /// ثبت قبلی را کامل باطل و از صفر دوباره ثبت می‌کند — دقیقاً همان کاری
    /// که قبلاً فقط بستن و باز کردن کامل اپ انجام می‌داد.
    private fun hardReset(result: MethodChannel.Result) {
        try {
            val device = connectedDevice
            if (device != null) {
                try { hidDevice?.disconnect(device) } catch (e: Throwable) {}
            }
            try { hidDevice?.unregisterApp() } catch (e: Throwable) {}
        } catch (e: Throwable) {
            // نادیده گرفته می‌شود — هدف فقط پاک‌سازی وضعیت است
        }
        registered = false
        registering = false
        hidDevice = null
        connectedDevice = null
        registerHid(result)
    }

    private fun sendConsumerUsage(usage: Int): Boolean {
        val device = connectedDevice ?: return false
        val hid = hidDevice ?: return false
        val press = byteArrayOf((usage and 0xFF).toByte(), ((usage shr 8) and 0xFF).toByte())
        val ok = try {
            hid.sendReport(device, REPORT_ID_CONSUMER.toInt(), press)
        } catch (e: Throwable) {
            false
        }
        mainHandler.postDelayed({
            // ⚠️ رفع باگ کرش: postDelayed روی main looper اجرا می‌شود — هر
            // استثنای دستنگیرنشده اینجا (مثل IllegalStateException هنگام ریست
            // پروفایل HID یا DeadObjectException اگر سرویس بلوتوث کرش کند، یا
            // حتی یک java.lang.Error روی پشته‌ی بلوتوث بعضی سازنده‌ها) مستقیماً
            // اپ را از کار می‌اندازد. Throwable هر دو Exception و Error را می‌گیرد.
            try {
                hid.sendReport(device, REPORT_ID_CONSUMER.toInt(), byteArrayOf(0, 0))
            } catch (e: Throwable) {
                // نادیده گرفته می‌شود
            }
        }, RELEASE_DELAY_MS)
        return ok
    }

    private fun sendKeyboardUsage(usage: Int): Boolean {
        val device = connectedDevice ?: return false
        val hid = hidDevice ?: return false
        // ⚠️ رفع باگ HID: کدهای 0xE0-0xE7 کلیدهای Modifier هستند (LCtrl, LShift,
        // LAlt, LMeta, RCtrl, RShift, RAlt, RMeta). این کدها باید در بایت صفرم
        // گزارش (modifier byte) به‌صورت bitmask قرار گیرند، نه در جایگاه keycode
        // (بایت دوم). قبلاً shift (0xE1) در بایت keycode فرستاده می‌شد که خلاف
        // مشخصات HID است و برخی دستگاه‌ها آن را نادیده می‌گرفتند.
        val press = if (usage in 0xE0..0xE7) {
            val modifierBit = 1 shl (usage - 0xE0)  // 0xE1→bit1=0x02=LShift
            byteArrayOf(modifierBit.toByte(), 0, 0, 0, 0, 0, 0, 0)
        } else {
            byteArrayOf(0, 0, usage.toByte(), 0, 0, 0, 0, 0)
        }
        val ok = try {
            hid.sendReport(device, REPORT_ID_KEYBOARD.toInt(), press)
        } catch (e: Throwable) {
            false
        }
        mainHandler.postDelayed({
            // ⚠️ رفع باگ کرش: مانند release مربوط به Consumer، اینجا هم
            // همه‌ی خطاها (Exception و Error) باید گرفته شوند تا main looper کرش نکند.
            try {
                hid.sendReport(device, REPORT_ID_KEYBOARD.toInt(), ByteArray(8))
            } catch (e: Throwable) {
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
        } catch (e: Throwable) {
            false
        }
    }

    private fun sendMouseClick(): Boolean {
        // کنسل کردن release معلق قبلی تا با button-down جدید تداخل نداشته باشد
        pendingMouseRelease?.let { mainHandler.removeCallbacks(it) }
        val down = sendMouseReport(1, 0, 0)
        val release = Runnable { sendMouseReport(0, 0, 0) }
        pendingMouseRelease = release
        mainHandler.postDelayed(release, RELEASE_DELAY_MS)
        return down
    }
}
