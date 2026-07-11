import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// وضعیت اتصال بلوتوث برای نمایش در UI (status bar بالای صفحه)
enum BtConnState { disconnected, scanning, connecting, connected, error }

/// سرویس واقعی بلوتوث کم‌مصرف (BLE).
///
/// ⚠️ نکته مهم: چون کنترل بلوتوثی دوو یک دستگاه اختصاصی و غیر-استاندارد است،
/// UUID سرویس/کاراکتریستیک GATT واقعی آن (که فرمان‌ها از طریقش نوشته می‌شود)
/// در دسترس عموم نیست. مقادیر زیر (serviceUuid / writeCharUuid) باید با استفاده
/// از یک ابزار BLE Scanner (مثل nRF Connect) روی کنترل واقعی کشف و جایگزین شوند:
/// ۱. کنترل را با nRF Connect اسکن کنید و به آن وصل شوید
/// ۲. لیست Services و Characteristics را ببینید
/// ۳. مشخصه‌ای که Write/Write No Response دارد را پیدا کنید -> همان writeCharUuid است
class BluetoothService {
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  // TODO: با UUID واقعی کشف‌شده از کنترل دوو جایگزین شود
  static final Guid serviceUuid = Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
  static final Guid writeCharUuid = Guid('0000ffe1-0000-1000-8000-00805f9b34fb');

  final _stateController = StreamController<BtConnState>.broadcast();
  Stream<BtConnState> get stateStream => _stateController.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool get isConnected => _device != null && _writeChar != null;

  /// اسکن دستگاه‌های بلوتوثی اطراف.
  /// نکته: چون نام واقعی تبلیغاتی (advertising name) کنترل بلوتوثی دوو مشخص
  /// نیست، همه‌ی دستگاه‌های اطراف نمایش داده می‌شوند، ولی دستگاه‌هایی که در نام‌شان
  /// "daewoo" یا "dw" باشد اول لیست قرار می‌گیرند تا سریع‌تر پیدا شوند. وقتی نام
  /// دقیق کنترل را متوجه شدید، می‌توانید فیلتر را در پایین سخت‌گیرانه‌تر کنید.
  /// قبل از صدا زدن این متد باید مجوزهای بلوتوث گرفته شده باشند (PermissionsService).
  Stream<List<ScanResult>> scanForDaewooRemotes({
    Duration timeout = const Duration(seconds: 8),
  }) {
    _stateController.add(BtConnState.scanning);
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map((results) {
      final sorted = [...results];
      sorted.sort((a, b) {
        bool likely(ScanResult r) {
          final n = r.device.platformName.toLowerCase();
          return n.contains('daewoo') || n.contains('dw');
        }

        final aLikely = likely(a) ? 0 : 1;
        final bLikely = likely(b) ? 0 : 1;
        return aLikely.compareTo(bLikely);
      });
      return sorted;
    });
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// اتصال واقعی به دستگاه انتخاب‌شده و کشف Service/Characteristic نوشتن.
  Future<bool> connect(BluetoothDevice device) async {
    await stopScan();
    _stateController.add(BtConnState.connecting);
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _writeChar = null;
          _device = null;
          _stateController.add(BtConnState.disconnected);
        }
      });

      final services = await device.discoverServices();
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            // اولویت با UUID مشخص‌شده بالا؛ در غیر این صورت اولین کاراکتریستیک قابل‌نوشتن
            if (c.uuid == writeCharUuid || _writeChar == null) {
              _writeChar = c;
            }
          }
        }
      }

      if (_writeChar == null) {
        _stateController.add(BtConnState.error);
        return false;
      }

      _stateController.add(BtConnState.connected);
      return true;
    } catch (e) {
      _stateController.add(BtConnState.error);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    _stateController.add(BtConnState.disconnected);
  }

  /// ارسال یک فرمان متنی (مثلاً "POWER", "VOL_UP") به کنترل.
  /// فرمت واقعی بایت‌های پروتکل کنترل دوو مشخص نیست، پس این متد رشته
  /// فرمان را به UTF-8 تبدیل و می‌نویسد؛ اگر پروتکل واقعی بایتی/باینری
  /// خاصی داشت (مثلاً کد هگزادسیمال)، باید در اینجا جایگزین شود.
  Future<bool> sendCommand(String command) async {
    if (_writeChar == null) return false;
    try {
      final bytes = utf8.encode(command);
      await _writeChar!.write(bytes, withoutResponse: _writeChar!.properties.writeWithoutResponse);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ارسال مختصات حرکت موس (برای تاچ‌پد کنترل کوچک بلوتوثی)
  Future<bool> sendMouseMove(int dx, int dy) => sendCommand('MOUSE:$dx,$dy');

  Future<bool> sendMouseClick() => sendCommand('MOUSE_CLICK');

  Future<bool> setMicActive(bool active) =>
      sendCommand(active ? 'MIC_ON' : 'MIC_OFF');

  void dispose() {
    _connSub?.cancel();
    _stateController.close();
  }
}
