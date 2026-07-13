import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'theme/colors.dart';

void main() {
  // ⚠️ رفع باگ کرش: قبلاً هیچ گیرنده‌ی سراسری خطا وجود نداشت. یک استثنای
  // دستنگیرنشده‌ی Dart (مثلاً در یک callback async خارج از چرخه‌ی build
  // ویجت‌ها — که FlutterError.onError آن را نمی‌گیرد) مستقیماً به بالاترین
  // سطح می‌رسید و کل اپ را می‌بست. حالا با runZonedGuarded این‌گونه
  // استثناها فقط لاگ می‌شوند و اپ باز می‌ماند.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // خطاهای فریم‌ورک فلاتر (مثل خطای build یک ویجت) به‌طور پیش‌فرض روی
    // release فقط صفحه‌ی خاکستری خالی نشان می‌دهند، نه crash کامل اپ —
    // ولی برای شفافیت بیشتر در لاگ (logcat/adb)، اینجا هم صریحاً لاگ
    // می‌کنیم تا در آینده اگر باز هم گزارش کرش شد، بشود از لاگ واقعی علت
    // را پیدا کرد.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // نکته: هیچ‌گونه مقداردهی اولیه‌ی SDK تبلیغاتی (AdMob/AppLovin/Tapsell/Facebook)
    // یا سرویس پرداخت/اشتراک (Poolakey) در این نسخه وجود ندارد — طبق درخواست کاربر.
    runApp(const DaewooRemoteApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class DaewooRemoteApp extends StatelessWidget {
  const DaewooRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'کنترل هوشمند دوو',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('fa', 'IR'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const WelcomeScreen(),
    );
  }
}
