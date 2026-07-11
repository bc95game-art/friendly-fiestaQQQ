import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'theme/colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // نکته: هیچ‌گونه مقداردهی اولیه‌ی SDK تبلیغاتی (AdMob/AppLovin/Tapsell/Facebook)
  // یا سرویس پرداخت/اشتراک (Poolakey) در این نسخه وجود ندارد — طبق درخواست کاربر.
  runApp(const DaewooRemoteApp());
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
