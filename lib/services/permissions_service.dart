import 'package:permission_handler/permission_handler.dart';

/// درخواست واقعی مجوزهای رانتایم اندروید.
/// این‌ها باید در AndroidManifest.xml هم تعریف شده باشند (که در این پروژه هست).
class PermissionsService {
  PermissionsService._();

  /// مجوزهای لازم برای اسکن/اتصال بلوتوث (اندروید ۱۲+ از BLUETOOTH_SCAN و
  /// BLUETOOTH_CONNECT استفاده می‌کند؛ نسخه‌های قدیمی‌تر به ACCESS_FINE_LOCATION
  /// نیاز دارند چون اسکن BLE به موقعیت مکانی گره خورده است).
  static Future<bool> requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
  }

  /// مجوز میکروفون برای قابلیت ضبط صدا در کنترل کوچک بلوتوثی
  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// اندروید برای IR (ConsumerIrManager) مجوز runtime جداگانه‌ای در سطح
  /// permission_handler ندارد (TRANSMIT_IR یک permission عادی/normal است که
  /// فقط با اعلام در Manifest در نصب اعطا می‌شود)، اما وجود سخت‌افزار را
  /// باید جدا از طریق IrService.hasIrEmitter() چک کنیم.
  static Future<bool> checkBluetoothGranted() async {
    return await Permission.bluetoothConnect.isGranted &&
        await Permission.bluetoothScan.isGranted;
  }
}
