import 'dart:async';
import 'package:flutter/services.dart';
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

  final _stateController = StreamController<BtConnState>.broadcast();
  Stream<BtConnState> get stateStream => _stateController.stream;

  BtConnState _state = BtConnState.disconnected;
  BtConnState get state => _state;
  bool get isConnected => _state == BtConnState.connected;

  bool _listening = false;

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
      if (!ok) _emit(BtConnState.unsupported);
      return ok;
    } on PlatformException {
      _emit(BtConnState.unsupported);
      return false;
    } on MissingPluginException {
      _emit(BtConnState.unsupported);
      return false;
    }
  }

  /// دستگاه‌های بلوتوثی که قبلاً از تنظیمات گوشی Pair شده‌اند.
  /// تلویزیون باید ابتدا از تنظیمات بلوتوث خودِ گوشی Pair شود؛ این اپ
  /// خودش اسکن/Pair نمی‌کند — فقط از لیست دستگاه‌های از‌قبل‌جفت‌شده انتخاب می‌کند.
  Future<List<BtBondedDevice>> bondedDevices() async {
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
    } on PlatformException {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    _emit(BtConnState.connecting);
    try {
      final ok =
          await _channel.invokeMethod<bool>('connect', {'address': address}) ??
              false;
      if (!ok) _emit(BtConnState.error);
      return ok;
    } on PlatformException {
      _emit(BtConnState.error);
      return false;
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
}
