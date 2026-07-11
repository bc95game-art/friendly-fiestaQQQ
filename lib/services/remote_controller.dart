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

    // حالت IR
    final pattern = IrCodes.patternFor(commandKey);
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
