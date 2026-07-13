import 'package:flutter/services.dart';
import '../models/remote_mode.dart';
import 'bt_hid_service.dart';
import 'bt_hid_commands.dart';
import 'ir_service.dart';
import 'ir_codes.dart';

/// نتیجه‌ی ارسال یک دستور، برای نمایش پیام مناسب در UI (مثلاً SnackBar)
class CommandResult {
  final bool success;
  final String? message;
  const CommandResult(this.success, [this.message]);
}

/// هر دکمه‌ی کنترل، این کلاس را صدا می‌زند. بسته به حالت (bluetooth/ir)
/// دستور را از مسیر درست (HID بلوتوثی واقعی یا ConsumerIrManager) ارسال می‌کند.
class RemoteController {
  RemoteController(this.mode);
  final RemoteMode mode;

  /// رفع باگ «دکمه Back و Home در حالت IR تلویزیون را Freeze می‌کنند»:
  ///
  /// ریموت فیزیکی اصلی دوو ۱۳۶۳ دکمه‌ی Back یا Home ندارد، پس کد IR واقعی
  /// برای آن‌ها وجود ندارد. کدهای «مهندسی‌شده» که قبلاً استفاده می‌شد
  /// گاهی باعث Freeze لحظه‌ای تلویزیون می‌شد — احتمالاً به دلیل باگ firmware
  /// در پردازش کد ناشناخته توسط گیرنده IR تلویزیون.
  ///
  /// راه‌حل امن: دکمه‌های بدون کد IR واقعی به نزدیک‌ترین معادل عملکردی که
  /// از ریموت اصلی ضبط شده (و صد درصد کار می‌کند) تغییر مسیر می‌دهند:
  ///   • back  → exit  (کد واقعی «خروج» — مثل Back از برنامه/منو خارج می‌شود)
  ///   • home  → menu  (کد واقعی «منو» — به صفحه اصلی منوی تلویزیون می‌رود)
  static const _irFallback = <String, String>{
    'back': 'exit',
    'home': 'menu',
  };

  Future<CommandResult> send(String commandKey) async {
    HapticFeedback.lightImpact();

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

    // حالت IR — از جایگزین امن برای دکمه‌های بدون کد واقعی استفاده می‌کنیم
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
