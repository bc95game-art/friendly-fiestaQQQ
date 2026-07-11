import 'package:flutter/services.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  RemoteInputHandler — لایه انتزاعی ریموت فیزیکی بلوتوثی HID
// ══════════════════════════════════════════════════════════════════════════════
//
//  ریموت فیزیکی دوو از پروفایل Bluetooth HID استاندارد استفاده می‌کند (نه BLE).
//  وقتی به گوشی Pair شود، دکمه‌هایش دقیقاً مثل یک کیبورد به Flutter می‌رسند.
//
//  کدهای شناخته‌شده (تست‌شده با مرورگر):
//    ArrowLeft       keyCode 37  → channelDown
//    ArrowRight      keyCode 39  → channelUp
//    MediaPlayPause  keyCode 179 → togglePlayPause
//
//  برای دکمه‌های ناشناخته:
//    ۱. صفحه Debug را باز کنید (آیکون 🪲 در AppBar کنترل بلوتوثی)
//    ۲. هر دکمه را فشار دهید
//    ۳. مقدار logicalId (مثلاً 0x100070044) را یادداشت کنید
//    ۴. در بخش customKeyMap زیر اضافه کنید
// ══════════════════════════════════════════════════════════════════════════════

/// اکشن‌های منطقی که ریموت فیزیکی می‌تواند اجرا کند
enum RemoteAction {
  volumeUp,
  volumeDown,
  channelUp,
  channelDown,
  togglePlayPause,
  back,
  ok,
  /// برای دکمه‌های ناشناخته — بعد از تست با Debug Screen مقدار واقعی جایگزین کنید
  custom1,
  custom2,
}

class RemoteInputHandler {
  RemoteInputHandler._();

  // ── نگاشت پیش‌فرض (دکمه‌های شناخته‌شده) ─────────────────────────────────
  static final Map<LogicalKeyboardKey, RemoteAction> _defaultMap = {
    LogicalKeyboardKey.arrowLeft:      RemoteAction.channelDown,
    LogicalKeyboardKey.arrowRight:     RemoteAction.channelUp,
    LogicalKeyboardKey.mediaPlayPause: RemoteAction.togglePlayPause,
    LogicalKeyboardKey.arrowUp:        RemoteAction.volumeUp,
    LogicalKeyboardKey.arrowDown:      RemoteAction.volumeDown,
    LogicalKeyboardKey.goBack:         RemoteAction.back,
    LogicalKeyboardKey.select:         RemoteAction.ok,
    LogicalKeyboardKey.enter:          RemoteAction.ok,
  };

  // ── نگاشت سفارشی — اینجا دکمه‌های ناشناخته را اضافه کنید ────────────────
  //
  // مثال (بعد از کشف کد با صفحه Debug):
  //   LogicalKeyboardKey(0x100070XXX): RemoteAction.custom1,
  //   LogicalKeyboardKey(0x100070YYY): RemoteAction.custom2,
  //
  static final Map<LogicalKeyboardKey, RemoteAction> customKeyMap = {
    // ← کدهای ناشناخته را اینجا اضافه کنید
  };

  // ── نگاشت اکشن → کلید دستور نرم‌افزاری (برای ارسال IR یا BT) ─────────────
  static const Map<RemoteAction, String> _actionToCommand = {
    RemoteAction.volumeUp:        'vol_up',
    RemoteAction.volumeDown:      'vol_down',
    RemoteAction.channelUp:       'ch_up',
    RemoteAction.channelDown:     'ch_down',
    RemoteAction.togglePlayPause: 'play_pause',
    RemoteAction.back:            'back',
    RemoteAction.ok:              'ok',
    // custom1 و custom2 تا زمانی که کد واقعی مشخص نشود، null برمی‌گردانند
  };

  /// یک KeyEvent را به RemoteAction تبدیل می‌کند؛ اگر شناسایی نشد null.
  /// فقط KeyDownEvent پردازش می‌شود (نه KeyUp / KeyRepeat).
  static RemoteAction? resolve(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    return _defaultMap[event.logicalKey] ?? customKeyMap[event.logicalKey];
  }

  /// RemoteAction را به کلید دستور نرم‌افزاری تبدیل می‌کند.
  /// مثلاً RemoteAction.channelUp → 'ch_up'
  static String? toCommandKey(RemoteAction action) =>
      _actionToCommand[action];
}
