import 'package:flutter/services.dart';
import '../models/remote_mode.dart';
import 'bt_hid_service.dart';
import 'bt_hid_commands.dart';
import 'ir_service.dart';
import 'ir_codes.dart';
import 'wifi_remote_service.dart';

/// نتیجه‌ی ارسال یک دستور، برای نمایش پیام مناسب در UI
class CommandResult {
  final bool success;
  final String? message;
  const CommandResult(this.success, [this.message]);
}

/// هر دکمه‌ی کنترل، این کلاس را صدا می‌زند. بسته به حالت (bluetooth/ir/wifi)
/// دستور را از مسیر درست ارسال می‌کند.
class RemoteController {
  RemoteController(this.mode);
  final RemoteMode mode;

  /// ⚠️ رفع باگ گزارش‌شده «دکمه Home و Back در IR کار نمی‌کند»:
  ///
  /// ریموت فیزیکی اصلی دوو ۱۳۶۳ نه دکمه Home دارد نه Back.
  /// کاربر تأیید کرده که دکمه EXIT همان عملکرد هر دو را دارد
  /// (از منو/برنامه خارج می‌کند).
  ///
  /// قبلاً: home → menu  (اشتباه — منو باز می‌کرد نه خروج)
  /// حالا:  home → exit  (درست — مثل EXIT ریموت اصلی عمل می‌کند)
  static const _irFallback = <String, String>{
    'back': 'exit',
    'home': 'exit',
  };

  Future<CommandResult> send(String commandKey) async {
    HapticFeedback.lightImpact();

    // ── حالت بلوتوث ───────────────────────────────────────────────────
    if (mode.isBluetooth) {
      if (!BtHidService.instance.isConnected) {
        return const CommandResult(false, 'ابتدا به بلوتوث تلویزیون متصل شوید');
      }
      if (!BtHidCommands.map.containsKey(commandKey)) {
        return const CommandResult(
          false,
          'این دکمه در حالت بلوتوث پشتیبانی نمی‌شود — از حالت فرستنده IR استفاده کنید',
        );
      }
      final ok = await BtHidService.instance.sendCommand(commandKey);
      return CommandResult(ok, ok ? null : 'ارسال فرمان با خطا مواجه شد');
    }

    // ── حالت وای‌فای ──────────────────────────────────────────────────
    if (mode.isWifi) {
      if (!WifiRemoteService.instance.isConnected) {
        return const CommandResult(false, 'اتصال وای‌فای برقرار نیست — برگردید');
      }
      final ok = await WifiRemoteService.instance.sendKey(commandKey);
      return CommandResult(ok, ok ? null : 'ارسال دستور با خطا مواجه شد');
    }

    // ── حالت IR ───────────────────────────────────────────────────────
    // از جایگزین امن برای دکمه‌های بدون کد واقعی استفاده می‌کنیم
    final irKey = _irFallback[commandKey] ?? commandKey;
    final pattern = IrCodes.patternFor(irKey);
    if (pattern == null) {
      return CommandResult(
        false,
        'کد IR دکمه «$commandKey» هنوز تنظیم نشده (ir_codes.dart را ببینید)',
      );
    }
    final ok = await IrService.instance.transmit(
      frequencyHz: IrCodes.carrierFrequencyHz,
      pattern: pattern,
    );
    return CommandResult(ok, ok ? null : 'گوشی شما فرستنده IR سخت‌افزاری ندارد');
  }
}
