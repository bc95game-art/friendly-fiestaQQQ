import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bt_hid_commands.dart';

/// وضعیت اتصال بلوتوث تلویزیون برای نمایش در UI.
enum BtConnState { disconnected, connecting, connected, error, unsupported }

/// یک دستگاه بلوتوثی که قبلاً از تنظیمات گوشی Pair شده (bonded) است.
class BtBondedDevice {
  final String name;
  final String address;
  const BtBondedDevice(this.name, this.address);
}

/// ══════════════════════════════════════════════════════════════════════
///  BtHidService — گوشی را مستقیماً به‌عنوان یک دستگاه HID بلوتوثی
///  (کیبورد + کنترل چندرسانه‌ای + موس) به تلویزیون معرفی می‌کند.
/// ══════════════════════════════════════════════════════════════════════
///
///  چرا این روش؟ چون تلویزیون شما یک Android TV واقعی است، سیستم‌عامل آن
///  از پروفایل استاندارد Bluetooth HID Device پشتیبانی می‌کند — دقیقاً
///  همان‌طور که یک کیبورد یا ریموت بلوتوثی معمولی با آن کار می‌کند. این
///  یعنی به هیچ UUID یا پروتکل اختصاصی و ناشناخته‌ی «کنترل دوو» نیاز نیست.
///
///  مراحل استفاده (سمت کاربر):
///   ۱. از تنظیمات گوشی → بلوتوث، تلویزیون را Pair کنید (مثل هر دستگاه دیگر)
///   ۲. داخل اپ، از لیست دستگاه‌های Pair‌شده تلویزیون را انتخاب کنید
///   ۳. اپ به تلویزیون متصل می‌شود و از آن پس دکمه‌ها را مثل یک ریموت/کیبورد
///      بلوتوثی واقعی ارسال می‌کند.
///
///  پیاده‌سازی نیتیو در MainActivity.kt (کانال daewoo/bt_hid) با
///  BluetoothHidDevice انجام شده — نیازمند اندروید ۹ (API 28) به بالا.
class BtHidService {
  BtHidService._();
  static final BtHidService instance = BtHidService._();

  static const _channel = MethodChannel('daewoo/bt_hid');
  static const _events = EventChannel('daewoo/bt_hid/state');

  // کلید ذخیره‌ی آدرس آخرین دستگاه متصل‌شده (برای اتصال خودکار بدون لمس دستی).
  static const _lastDeviceKey = 'bt_last_device_address';

  final _stateController = StreamController<BtConnState>.broadcast();
  Stream<BtConnState> get stateStream => _stateController.stream;

  BtConnState _state = BtConnState.disconnected;
  BtConnState get state => _state;
  bool get isConnected => _state == BtConnState.connected;

  bool _listening = false;

  /// آخرین دلیل مشخص (نه حدسی) شکست initialize()/register — برای نمایش
  /// پیام درست به کاربر به‌جای پیام یکسان و گاهی غلط «نسخه اندروید».
  String? lastInitError;

  void _emit(BtConnState s) {
    _state = s;
    _stateController.add(s);
  }

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _events.receiveBroadcastStream().listen((event) {
      switch (event as String) {
        case 'connected':
          _emit(BtConnState.connected);
          break;
        case 'connecting':
          _emit(BtConnState.connecting);
          break;
        case 'disconnected':
          _emit(BtConnState.disconnected);
          break;
        default:
          _emit(BtConnState.error);
      }
    });
  }

  /// این گوشی را به‌عنوان دستگاه HID بلوتوثی نزد سیستم‌عامل ثبت می‌کند.
  /// باید قبل از تلاش برای اتصال صدا زده شود. روی اندروید کمتر از ۹
  /// یا گوشی‌هایی بدون پشتیبانی از پروفایل HID Device، false برمی‌گرداند.
  Future<bool> initialize() async {
    _ensureListening();
    try {
      final ok = await _channel.invokeMethod<bool>('register') ?? false;
      if (!ok) {
        lastInitError = 'ثبت پروفایل HID بلوتوث ناموفق بود';
        _emit(BtConnState.error);
      }
      return ok;
    } on PlatformException catch (e) {
      // ⚠️ رفع باگ: قبلاً هر شکستی (خاموش‌بودن بلوتوث، نبود سخت‌افزار، یا
      // واقعاً نسخه‌ی قدیمی اندروید) با یک وضعیت یکسان (unsupported) و یک
      // پیام ثابت و گاهی غلط («نسخه اندروید شما پشتیبانی نمی‌کند») نشان
      // داده می‌شد. حالا کد خطای واقعی از سمت نیتیو خوانده می‌شود تا فقط
      // در حالت واقعاً ناسازگار (sdk_unsupported / no_bluetooth_hardware)
      // پیام «پشتیبانی نمی‌شود» نشان داده شود.
      switch (e.code) {
        case 'sdk_unsupported':
        case 'no_bluetooth_hardware':
          lastInitError = e.message;
          _emit(BtConnState.unsupported);
          break;
        case 'bluetooth_disabled':
          lastInitError = e.message ?? 'بلوتوث گوشی خاموش است — آن را روشن کنید';
          _emit(BtConnState.error);
          break;
        default:
          lastInitError = e.message ?? 'خطای نامشخص در راه‌اندازی بلوتوث';
          _emit(BtConnState.error);
      }
      return false;
    } on MissingPluginException {
      lastInitError = 'این گوشی از حالت کنترل بلوتوثی پشتیبانی نمی‌کند';
      _emit(BtConnState.unsupported);
      return false;
    }
  }

  /// دستگاه‌های بلوتوثی که قبلاً از تنظیمات گوشی Pair شده‌اند.
  /// تلویزیون باید ابتدا از تنظیمات بلوتوث خودِ گوشی Pair شود؛ این اپ
  /// خودش اسکن/Pair نمی‌کند — فقط از لیست دستگاه‌های از‌قبل‌جفت‌شده انتخاب می‌کند.
  /// اگر true باشد، آخرین فراخوانی bondedDevices/connect به‌خاطر نبودِ
  /// واقعیِ مجوز BLUETOOTH_CONNECT (نه نبودِ دستگاه Pair‌شده) شکست خورده.
  /// UI باید بر اساس این پرچم پیام درست را نشان دهد، نه «دستگاهی یافت نشد».
  bool lastCallWasPermissionDenied = false;

  Future<List<BtBondedDevice>> bondedDevices() async {
    lastCallWasPermissionDenied = false;
    try {
      final result =
          await _channel.invokeMethod<List<Object?>>('bondedDevices') ?? [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map((m) {
            final name = (m['name'] as String?) ?? '';
            return BtBondedDevice(
              name.trim().isEmpty ? '(بدون نام)' : name,
              m['address'] as String,
            );
          })
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') lastCallWasPermissionDenied = true;
      return [];
    }
  }

  Future<bool> connect(String address) async {
    lastCallWasPermissionDenied = false;
    _emit(BtConnState.connecting);
    try {
      final ok =
          await _channel.invokeMethod<bool>('connect', {'address': address}) ??
              false;
      if (!ok) {
        _emit(BtConnState.error);
      } else {
        // برای اتصال خودکار در دفعات بعدی (رفع باگ «اتصال خودکار بلوتوث»)
        await _rememberDevice(address);
      }
      return ok;
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') lastCallWasPermissionDenied = true;
      _emit(BtConnState.error);
      return false;
    }
  }

  Future<void> _rememberDevice(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDeviceKey, address);
    } catch (_) {
      // ذخیره‌سازی اختیاری است؛ شکست آن نباید باعث خرابی اتصال شود
    }
  }

  /// آدرس آخرین دستگاهی که با موفقیت وصل شده — برای تلاش خودکار در شروع
  /// اپ و بعد از بازگشت از پس‌زمینه، بدون نیاز به لمس دستی کاربر.
  Future<String?> lastDeviceAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastDeviceKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } on PlatformException {
      // نادیده گرفته می‌شود — وضعیت با رویداد disconnected به‌روزرسانی می‌شود
    } finally {
      _emit(BtConnState.disconnected);
    }
  }

  /// ارسال یک دستور منطقی (مثلاً 'vol_up') به‌صورت یک فشار-و-رهای HID واقعی.
  /// اگر برای این کلید نگاشت HID تعریف نشده باشد، false برمی‌گرداند —
  /// دکمه فراخوان (RemoteController) این حالت را با پیام صریح مدیریت می‌کند.
  Future<bool> sendCommand(String key) async {
    final cmd = BtHidCommands.map[key];
    if (cmd == null || !isConnected) return false;
    try {
      return await _channel.invokeMethod<bool>(
            cmd.consumer ? 'sendConsumer' : 'sendKeyboard',
            {'usage': cmd.usage},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// حرکت نسبی موس (برای تاچ‌پد کنترل کوچک)
  Future<bool> sendMouseMove(int dx, int dy) async {
    if (!isConnected) return false;
    try {
      return await _channel
              .invokeMethod<bool>('sendMouseMove', {'dx': dx, 'dy': dy}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> sendMouseClick() async {
    if (!isConnected) return false;
    try {
      return await _channel.invokeMethod<bool>('sendMouseClick') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// روش جایگزین اتصال: گوشی را برای ۱۲۰ ثانیه «قابل مشاهده» می‌کند تا
  /// کاربر از روی خودِ تلویزیون (نه از این اپ) به آن وصل شود. این روش
  /// وقتی «اتصال از گوشی» مدام قطع می‌شود (وضعیت بین در-حال-اتصال و
  /// قطع‌شده نوسان می‌کند) قابل‌اعتمادتر است — چون بعضی تلویزیون‌ها فقط
  /// وقتی خودشان شروع‌کننده‌ی اتصال HID باشند آن را می‌پذیرند.
  Future<bool> requestDiscoverable() async {
    try {
      return await _channel.invokeMethod<bool>('requestDiscoverable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// نام بلوتوثی این گوشی — برای راهنمایی کاربر که دنبال چه نامی در لیست
  /// بلوتوث تلویزیون بگردد.
  Future<String?> localDeviceName() async {
    try {
      return await _channel.invokeMethod<String>('localName');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
