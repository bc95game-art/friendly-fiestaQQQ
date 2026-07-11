import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/remote_mode.dart';
import '../services/bluetooth_service.dart';
import '../services/remote_controller.dart';
import '../services/remote_input_handler.dart';
import '../theme/colors.dart';
import '../widgets/remote_button.dart';
import '../widgets/touchpad.dart';
import 'bt_debug_screen.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.mode, required this.size});
  final RemoteMode mode;
  final RemoteSize size;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final RemoteController _controller = RemoteController(widget.mode);
  BtConnState _btState = BtConnState.disconnected;
  StreamSubscription<BtConnState>? _btSub;

  // ── دیباونس: جلوگیری از ارسال چند فرمان همزمان هنگام ضربه‌های سریع ──
  DateTime? _lastPressTime;

  // ── برای نمایش feedback دکمه فیزیکی ──────────────────────────────────
  RemoteAction? _lastPhysicalAction;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    if (widget.mode.isBluetooth) {
      _btSub = BluetoothService.instance.stateStream.listen((s) {
        if (mounted) setState(() => _btState = s);
      });
      _autoConnect();
      // گوش دادن به کیبورد سخت‌افزاری (ریموت فیزیکی HID)
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
    }
  }

  // ── هندلر دکمه‌های ریموت فیزیکی بلوتوثی (HID) ────────────────────────
  bool _onHardwareKey(KeyEvent event) {
    final action = RemoteInputHandler.resolve(event);
    if (action == null) return false;

    final commandKey = RemoteInputHandler.toCommandKey(action);
    if (commandKey != null) {
      _press(commandKey);
      // نمایش کوتاه نام اکشن روی صفحه
      setState(() => _lastPhysicalAction = action);
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _lastPhysicalAction = null);
      });
    }
    // true = رویداد مصرف شد (به جاهای دیگر نرسد)
    return true;
  }

  Future<void> _autoConnect() async {
    await _pickDevice(auto: true);
  }

  Future<void> _pickDevice({bool auto = false}) async {
    final results = <ScanResult>[];
    final sub = BluetoothService.instance.scanForDaewooRemotes().listen((r) {
      results
        ..clear()
        ..addAll(r);
    });
    await Future.delayed(const Duration(seconds: 4));
    await sub.cancel();
    await BluetoothService.instance.stopScan();

    if (!mounted) return;
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ دستگاه بلوتوثی پیدا نشد — دوباره تلاش کنید')),
      );
      return;
    }

    // اتصال خودکار فقط اگر دستگاه در نامش «daewoo» یا «dw» باشد
    if (auto && results.length == 1) {
      final name = results.first.device.platformName.toLowerCase();
      if (name.contains('daewoo') || name.contains('dw')) {
        await BluetoothService.instance.connect(results.first.device);
        return;
      }
    }

    if (!mounted) return;
    final chosen = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: results
            .map((r) => ListTile(
                  leading: const Icon(Icons.bluetooth, color: AppColors.btAccent),
                  title: Text(
                    r.device.platformName.isEmpty ? '(بدون نام)' : r.device.platformName,
                    style: const TextStyle(color: AppColors.text1),
                  ),
                  subtitle: Text(r.device.remoteId.str,
                      style: const TextStyle(color: AppColors.text3)),
                  onTap: () => Navigator.pop(context, r.device),
                ))
            .toList(),
      ),
    );
    if (chosen != null) {
      await BluetoothService.instance.connect(chosen);
    }
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _feedbackTimer?.cancel();
    if (widget.mode.isBluetooth) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    super.dispose();
  }

  // ── ارسال دستور با دیباونس ۲۵۰ms ────────────────────────────────────────
  Future<void> _press(String key) async {
    final now = DateTime.now();
    if (_lastPressTime != null &&
        now.difference(_lastPressTime!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastPressTime = now;

    final result = await _controller.send(key);
    if (!result.success && result.message != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message!)));
    }
  }

  String get _statusText {
    if (widget.mode.isIr) return 'آماده ارسال سیگنال';
    switch (_btState) {
      case BtConnState.connected:
        return 'متصل به کنترل دوو';
      case BtConnState.connecting:
        return 'در حال اتصال…';
      case BtConnState.scanning:
        return 'در حال جستجو…';
      case BtConnState.error:
        return 'خطا در اتصال — لمس کنید';
      case BtConnState.disconnected:
        return 'متصل نیست — لمس کنید';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mode.isBluetooth ? AppColors.btAccent : AppColors.irAccent;
    final connected = widget.mode.isIr || _btState == BtConnState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.size == RemoteSize.large ? 'کنترل بزرگ' : 'کنترل کوچک'),
        actions: [
          if (widget.mode.isBluetooth) ...[
            // دکمه Debug — شناسایی دکمه‌های ریموت فیزیکی
            IconButton(
              icon: const Icon(Icons.bug_report_rounded),
              tooltip: 'Debug دکمه‌های ریموت فیزیکی',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BtDebugScreen()),
              ),
            ),
            // دکمه تغییر دستگاه BT
            IconButton(
              icon: Icon(Icons.bluetooth_searching_rounded,
                  color: connected ? AppColors.success : AppColors.text3),
              tooltip: 'تغییر دستگاه بلوتوث',
              onPressed: () => _pickDevice(),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: connected ? AppColors.success : AppColors.text3,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(_statusText,
                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: widget.size == RemoteSize.large
                  ? _LargeRemote(accent: accent, onPress: _press)
                  : _SmallRemote(accent: accent, mode: widget.mode, onPress: _press),
            ),
          ),
          // ── Feedback روی صفحه وقتی دکمه فیزیکی فشار داده می‌شود ──────
          if (_lastPhysicalAction != null)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _lastPhysicalAction != null ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(color: accent.withOpacity(0.4), blurRadius: 16),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bluetooth_rounded,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          _physicalActionLabel(_lastPhysicalAction!),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _physicalActionLabel(RemoteAction action) {
    switch (action) {
      case RemoteAction.channelUp:        return 'کانال بالا ▲';
      case RemoteAction.channelDown:      return 'کانال پایین ▼';
      case RemoteAction.volumeUp:         return 'صدا بیشتر +';
      case RemoteAction.volumeDown:       return 'صدا کمتر −';
      case RemoteAction.togglePlayPause:  return 'پخش / توقف ⏯';
      case RemoteAction.back:             return 'برگشت ↩';
      case RemoteAction.ok:               return 'تأیید ✓';
      case RemoteAction.custom1:          return 'دکمه سفارشی ۱';
      case RemoteAction.custom2:          return 'دکمه سفارشی ۲';
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
//  کنترل بزرگ
// ════════════════════════════════════════════════════════════════════════
class _LargeRemote extends StatelessWidget {
  const _LargeRemote({required this.accent, required this.onPress});
  final Color accent;
  final void Function(String) onPress;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.square,
                accent: AppColors.danger.withOpacity(0.25),
                onTap: () => onPress('power'),
                child: const Icon(Icons.power_settings_new_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.square,
                accent: accent.withOpacity(0.25),
                onTap: () => onPress('source'),
                child: const Icon(Icons.input_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            for (final n in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
              RemoteButton(
                  onTap: () => onPress('num_$n'),
                  child: Text(n, style: const TextStyle(fontSize: 16))),
            RemoteButton(
                onTap: () => onPress('return'),
                child: const Icon(Icons.replay_rounded)),
            RemoteButton(
                onTap: () => onPress('num_0'),
                child: const Text('0', style: TextStyle(fontSize: 16))),
            RemoteButton(
                onTap: () => onPress('info'),
                child: const Icon(Icons.info_outline_rounded)),
          ],
        ),
        const SizedBox(height: 16),
        _NavPad(onPress: onPress),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('vol_up'),
                    child: const Text('+', style: TextStyle(fontSize: 20)))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    accent: accent.withOpacity(0.25),
                    onTap: () => onPress('home'),
                    child: const Icon(Icons.home_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('ch_up'),
                    child: const Icon(Icons.keyboard_arrow_up_rounded))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('vol_down'),
                    child: const Text('−', style: TextStyle(fontSize: 20)))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('mute'),
                    child: const Icon(Icons.volume_off_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('ch_down'),
                    child: const Icon(Icons.keyboard_arrow_down_rounded))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ColorChip(Colors.red, () => onPress('color_red')),
            _ColorChip(Colors.green, () => onPress('color_green')),
            _ColorChip(Colors.amber, () => onPress('color_yellow')),
            _ColorChip(Colors.blue, () => onPress('color_blue')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('rewind'),
                    child: const Icon(Icons.fast_rewind_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('play_pause'),
                    child: const Icon(Icons.play_arrow_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('forward'),
                    child: const Icon(Icons.fast_forward_rounded))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    shape: RemoteButtonShape.tiny,
                    label: 'EXIT',
                    onTap: () => onPress('exit'),
                    child: const Icon(Icons.logout_rounded, size: 16))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('record'),
                    child: const Icon(Icons.fiber_manual_record_rounded,
                        color: AppColors.danger))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    shape: RemoteButtonShape.tiny,
                    label: 'EPG',
                    onTap: () => onPress('epg'),
                    child: const Icon(Icons.grid_view_rounded, size: 16))),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  کنترل کوچک
// ════════════════════════════════════════════════════════════════════════
class _SmallRemote extends StatelessWidget {
  const _SmallRemote(
      {required this.accent, required this.mode, required this.onPress});
  final Color accent;
  final RemoteMode mode;
  final void Function(String) onPress;

  @override
  Widget build(BuildContext context) {
    final locked = !mode.supportsMouseAndMic;
    return ListView(
      children: [
        Center(
          child: SizedBox(
            width: 64,
            child: RemoteButton(
              shape: RemoteButtonShape.square,
              accent: AppColors.danger.withOpacity(0.25),
              onTap: () => onPress('power'),
              child: const Icon(Icons.power_settings_new_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 64,
            child: RemoteButton(
              shape: RemoteButtonShape.square,
              accent: accent.withOpacity(0.2),
              disabled: locked,
              onTap: () => onPress('mic'),
              child: const Icon(Icons.mic_none_rounded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _NavPad(onPress: onPress),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('back'),
                    child: const Icon(Icons.arrow_back_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    accent: accent.withOpacity(0.2),
                    onTap: () => onPress('home'),
                    child: const Icon(Icons.home_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('menu'),
                    child: const Icon(Icons.menu_rounded))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('play_pause'),
                    child: const Icon(Icons.play_arrow_rounded))),
            const SizedBox(width: 8),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('source'),
                    child: const Icon(Icons.input_rounded))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('vol_up'),
                    child: const Text('+'))),
            Expanded(
              child: RemoteButton(
                disabled: locked,
                accent: accent.withOpacity(0.2),
                onTap: () => onPress('mouse_toggle'),
                child: const Icon(Icons.mouse_rounded),
              ),
            ),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('ch_up'),
                    child: const Icon(Icons.keyboard_arrow_up_rounded))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('vol_down'),
                    child: const Text('−'))),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('mute'),
                    child: const Icon(Icons.volume_off_rounded))),
            Expanded(
                child: RemoteButton(
                    onTap: () => onPress('ch_down'),
                    child: const Icon(Icons.keyboard_arrow_down_rounded))),
          ],
        ),
        const SizedBox(height: 16),
        Touchpad(locked: locked),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  NavPad — دایره ناوبری مرکزی
// ════════════════════════════════════════════════════════════════════════
class _NavPad extends StatelessWidget {
  const _NavPad({required this.onPress});
  final void Function(String) onPress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.panel2,
                    border: Border.all(color: AppColors.line)),
              ),
            ),
            Positioned(
                top: 0,
                child: _arrow(
                    Icons.keyboard_arrow_up_rounded, () => onPress('up'))),
            Positioned(
                bottom: 0,
                child: _arrow(
                    Icons.keyboard_arrow_down_rounded, () => onPress('down'))),
            Positioned(
                left: 0,
                child: _arrow(
                    Icons.keyboard_arrow_left_rounded, () => onPress('left'))),
            Positioned(
                right: 0,
                child: _arrow(Icons.keyboard_arrow_right_rounded,
                    () => onPress('right'))),
            SizedBox(
              width: 60,
              height: 60,
              child: RemoteButton(
                  shape: RemoteButtonShape.round,
                  onTap: () => onPress('ok'),
                  child: const Text('OK',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) => SizedBox(
        width: 48,
        height: 48,
        child:
            RemoteButton(shape: RemoteButtonShape.round, onTap: onTap, child: Icon(icon)),
      );
}

// ════════════════════════════════════════════════════════════════════════
//  دکمه‌های رنگی با انیمیشن فشار
// ════════════════════════════════════════════════════════════════════════
class _ColorChip extends StatefulWidget {
  const _ColorChip(this.color, this.onTap);
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ColorChip> createState() => _ColorChipState();
}

class _ColorChipState extends State<_ColorChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 2),
          ),
        ),
      ),
    );
  }
}
