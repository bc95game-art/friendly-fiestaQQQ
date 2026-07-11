import 'package:flutter/services.dart';

/// این سرویس با کد نیتیو اندروید (MainActivity.kt) که از ConsumerIrManager
/// استفاده می‌کند صحبت می‌کند. ConsumerIrManager فقط روی گوشی‌هایی که
/// چیپ IR سخت‌افزاری دارند کار می‌کند (اکثر گوشی‌های سامسونگ/شیائومی قدیمی‌تر
/// و برخی مدل‌های جدید دارند، آیفون و اکثر گوشی‌های جدید ندارند).
class IrService {
  IrService._();
  static final IrService instance = IrService._();

  static const _channel = MethodChannel('daewoo/ir');

  /// بررسی می‌کند که آیا گوشی سخت‌افزار فرستنده IR دارد یا نه.
  /// باید قبل از نمایش صفحه «فرستنده IR» صدا زده شود.
  Future<bool> hasIrEmitter() async {
    try {
      final bool result = await _channel.invokeMethod('hasIrEmitter');
      return result;
    } on PlatformException {
      return false;
    }
  }

  /// ارسال یک سیگنال IR با فرکانس حامل (carrier frequency به هرتز، معمولاً ۳۸۰۰۰ برای دوو)
  /// و الگوی pattern (آرایه‌ای از میکروثانیه‌های روشن/خاموش پیاپی).
  ///
  /// نکته مهم: کدهای واقعی IR تلویزیون‌های دوو باید از روی خودِ ریموت اصلی
  /// با یک گیرنده IR (یا اپ‌هایی مثل IR remote capture) ضبط و اینجا جایگزین شوند.
  /// در ادامه چند نمونه‌ی رایج NEC-protocol به‌عنوان الگو گذاشته شده که باید
  /// با کدهای واقعی ریموت شما اصلاح شوند (فایل ir_codes.dart).
  Future<bool> transmit({
    required int frequencyHz,
    required List<int> pattern,
  }) async {
    try {
      final bool ok = await _channel.invokeMethod('transmit', {
        'frequency': frequencyHz,
        'pattern': pattern,
      });
      return ok;
    } on PlatformException catch (e) {
      // خطاهای رایج: no_ir_emitter (گوشی چیپ IR ندارد) یا permission
      // ignore: avoid_print
      print('IR transmit error: ${e.code} - ${e.message}');
      return false;
    }
  }
}
