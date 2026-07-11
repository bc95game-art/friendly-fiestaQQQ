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
  /// این اپ دیگر خودش اسکن بلوتوثی انجام نمی‌دهد (دستگاه از لیست
  /// دستگاه‌های از‌قبل Pair‌شده‌ی گوشی انتخاب می‌شود)، پس فقط
  /// BLUETOOTH_CONNECT لازم است.
  static Future<PermissionResult> requestBluetoothPermissions() async {
    await Permission.bluetoothConnect.request();

    final connectGranted = await Permission.bluetoothConnect.isGranted ||
        await Permission.bluetoothConnect.isLimited;

    if (connectGranted) {
      return const PermissionResult(granted: true, permanentlyDenied: false);
    }

    final perma = await Permission.bluetoothConnect.isPermanentlyDenied;
    return PermissionResult(granted: false, permanentlyDenied: perma);
  }

  /// بررسی اینکه آیا مجوز بلوتوث از قبل داده شده (بدون نمایش دیالوگ)
  static Future<bool> checkBluetoothGranted() async {
    return await Permission.bluetoothConnect.isGranted;
  }
}
