import 'package:flutter/material.dart';

/// پالت رنگی هماهنگ با طرح HTML مرجع — با اضافه شدن رنگ وای‌فای
class AppColors {
  AppColors._();

  static const bg0    = Color(0xFF050608);
  static const bg1    = Color(0xFF0F1114);
  static const bg2    = Color(0xFF1A1E24);
  static const panel  = Color(0xFF232A32);
  static const panel2 = Color(0xFF2B3340);
  static const panel3 = Color(0xFF323B45);
  static const line      = Color(0xFF3D4655);
  static const lineLight = Color(0xFF4A5563);

  static const text1 = Color(0xFFF5F7FA);
  static const text2 = Color(0xFFA8B2BE);
  static const text3 = Color(0xFF6B7684);
  static const text4 = Color(0xFF4A5563);

  // بلوتوث — آبی
  static const btAccent      = Color(0xFF2E9FFF);
  static const btAccentLight = Color(0xFF5DBFFF);
  static const btAccentDim   = Color(0xFF0F2A4A);

  // فرستنده IR — نارنجی
  static const irAccent      = Color(0xFFFF8C42);
  static const irAccentLight = Color(0xFFFFB380);
  static const irAccentDim   = Color(0xFF4A2810);

  // وای‌فای — فیروزه‌ای/سبز
  static const wifiAccent      = Color(0xFF00C896);
  static const wifiAccentLight = Color(0xFF40E0B8);
  static const wifiAccentDim   = Color(0xFF003828);

  static const danger  = Color(0xFFFF5252);
  static const success = Color(0xFF26D07C);

  static const radiusLg = 32.0;
  static const radiusMd = 20.0;
  static const radiusSm = 12.0;
  static const radiusXs = 8.0;
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg0,
    fontFamily: 'Vazirmatn',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.btAccent,
      secondary: AppColors.irAccent,
      surface: AppColors.panel,
      error: AppColors.danger,
    ),
  );
}
