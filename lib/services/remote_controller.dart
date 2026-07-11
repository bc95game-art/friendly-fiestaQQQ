import 'package:flutter/services.dart';
import '../models/remote_mode.dart';
import 'bluetooth_service.dart';
import 'ir_service.dart';
import 'ir_codes.dart';

/// نتیجه‌ی ارسال یک دستور، برای نمایش پیام مناسب در UI (مثلاً SnackBar)
class CommandResult {
  final bool success;
  final String? message;
  const CommandResult(this.success, [this.message]);
}

/// هر دکمه‌ی کنترل، این کلاس را صدا می‌زند. بسته به حالت (bluetooth/ir)
/// دستور را از مسیر درست (GATT write یا ConsumerIrManager) واقعاً ارسال می‌کند.
class RemoteController {
  RemoteController(this.mode);
  final RemoteMode mode;

  Future<CommandResult> send(String commandKey) async {
    HapticFeedback.lightImpact();

    if (mode.isBluetooth) {
      if (!BluetoothService.instance.isConnected) {
        return const CommandResult(false, 'ابتدا به کنترل بلوتوثی متصل شوید');
      }
      final ok = await BluetoothService.instance.sendCommand(commandKey.toUpperCase());
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
