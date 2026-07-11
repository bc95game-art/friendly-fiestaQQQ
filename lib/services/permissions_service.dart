import 'package:permission_handler/permission_handler.dart';

/// نتیجه درخواست مجوز — برای تصمیم‌گیری در UI (باز کردن تنظیمات یا نمایش پیام)
class PermissionResult {
  final bool granted;

  /// اگر true: کاربر قبلاً مجوز را کاملاً رد کرده و دیالوگ سیستم دیگر نمایش داده نمی‌شود.
  /// در این حالت باید کاربر را به تنظیمات اپ هدایت کنیم.
  final bool permanentlyDenied;

  const PermissionResult({required this.granted, required this.permanentlyDenied});
}

/// درخواست واقعی مجوزهای رانتایم اندروید.
class PermissionsService {
  PermissionsService._();

  /// مجوزهای لازم برای اسکن/اتصال بلوتوث.
  ///
  /// ⚠️ نکته مهم درباره نسخه‌های اندروید:
  /// • اندروید ۱۲+ (API 31+): فقط BLUETOOTH_SCAN و BLUETOOTH_CONNECT کافی است.
  ///   ACCESS_FINE_LOCATION در این نسخه‌ها برای BLE اجباری نیست.
  /// • اندروید < ۱۲: اسکن BLE به ACCESS_FINE_LOCATION گره خورده است.
  ///
  /// این متد هر سه مجوز را درخواست می‌کند ولی فقط BT_SCAN و BT_CONNECT
  /// را به عنوان «اجباری» در نظر می‌گیرد — چون اندروید ۱۲+ بدون location هم کار می‌کند.
  static Future<PermissionResult> requestBluetoothPermissions() async {
    // درخواست همه‌ی مجوزها یکجا
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // برای اندروید < ۱۲
    ].request();

    // فقط BT_SCAN و BT_CONNECT اجباری هستند
    final scanGranted = await Permission.bluetoothScan.isGranted ||
        await Permission.bluetoothScan.isLimited;
    final connectGranted = await Permission.bluetoothConnect.isGranted ||
        await Permission.bluetoothConnect.isLimited;

    if (scanGranted && connectGranted) {
      return const PermissionResult(granted: true, permanentlyDenied: false);
    }

    // بررسی حالت permanently denied (دیالوگ دیگر نمایش داده نمی‌شود)
    final perma = await Permission.bluetoothScan.isPermanentlyDenied ||
        await Permission.bluetoothConnect.isPermanentlyDenied;

    return PermissionResult(granted: false, permanentlyDenied: perma);
  }

  /// مجوز میکروفون برای قابلیت ضبط صدا در کنترل کوچک بلوتوثی
  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// بررسی اینکه آیا مجوزهای بلوتوث از قبل داده شده‌اند (بدون نمایش دیالوگ)
  static Future<bool> checkBluetoothGranted() async {
    return await Permission.bluetoothConnect.isGranted &&
        await Permission.bluetoothScan.isGranted;
  }
}
