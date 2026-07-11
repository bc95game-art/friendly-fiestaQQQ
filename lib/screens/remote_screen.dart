import 'dart:async';
import 'package:flutter/material.dart';

import '../models/remote_mode.dart';
import '../services/bt_hid_service.dart';
import '../services/remote_controller.dart';
import '../theme/colors.dart';
import '../widgets/remote_button.dart';
import '../widgets/touchpad.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.mode.isBluetooth) {
      _btSub = BtHidService.instance.stateStream.listen((s) {
        if (mounted) setState(() => _btState = s);
      });
      _initBluetooth();
    }
  }

  Future<void> _initBluetooth() async {
    final supported = await BtHidService.instance.initialize();
    if (!mounted) return;
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'این گوشی از حالت کنترل بلوتوثی پشتیبانی نمی‌کند (نیاز به اندروید ۹ به بالا) — از حالت فرستنده IR استفاده کنید',
        ),
        duration: Duration(seconds: 5),
      ));
      return;
    }
    // اگر فقط یک دستگاه Pair شده وجود دارد، مستقیم به آن وصل شو
    final devices = await BtHidService.instance.bondedDevices();
    if (devices.length == 1 && mounted) {
      await BtHidService.instance.connect(devices.first.address);
    }
  }

  Future<void> _pickDevice() async {
    final devices = await BtHidService.instance.bondedDevices();
    if (!mounted) return;

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'هیچ دستگاهی پیدا نشد — اول باید بلوتوث تلویزیون را از «تنظیمات گوشی ← بلوتوث» Pair کنید',
        ),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    final chosen = await showModalBottomSheet<BtBondedDevice>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'بلوتوث تلویزیون خود را از لیست انتخاب کنید',
                  style: TextStyle(color: AppColors.text2, fontSize: 13),
                ),
              ),
            ),
            ...devices.map((d) => ListTile(
                  leading: const Icon(Icons.bluetooth, color: AppColors.btAccent),
                  title: Text(d.name, style: const TextStyle(color: AppColors.text1)),
                  subtitle: Text(d.address, style: const TextStyle(color: AppColors.text3)),
                  onTap: () => Navigator.pop(context, d),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await BtHidService.instance.connect(chosen.address);
    }
  }

  @override
  void dispose() {
    _btSub?.cancel();
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
        return 'متصل به بلوتوث تلویزیون';
      case BtConnState.connecting:
        return 'در حال اتصال به بلوتوث تلویزیون…';
      case BtConnState.unsupported:
        return 'این گوشی پشتیبانی نمی‌کند';
      case BtConnState.error:
        return 'خطا در اتصال — لمس کنید';
      case BtConnState.disconnected:
        return 'به بلوتوث تلویزیون متصل نیست — لمس کنید';
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
          if (widget.mode.isBluetooth)
            IconButton(
              icon: Icon(Icons.bluetooth_searching_rounded,
                  color: connected ? AppColors.success : AppColors.text3),
              tooltip: 'انتخاب بلوتوث تلویزیون',
              onPressed: _pickDevice,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: widget.mode.isBluetooth &&
                      _btState != BtConnState.connected &&
                      _btState != BtConnState.connecting
                  ? _pickDevice
                  : null,
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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: widget.size == RemoteSize.large
              ? _LargeRemote(accent: accent, onPress: _press)
              : _SmallRemote(accent: accent, mode: widget.mode, onPress: _press),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  کنترل بزرگ — تمام دکمه‌ها طبق طرح HTML مرجع
// ════════════════════════════════════════════════════════════════════════
class _LargeRemote extends StatelessWidget {
  const _LargeRemote({required this.accent, required this.onPress});
  final Color accent;
  final void Function(String) onPress;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ── ردیف ۱: Power + Source ──────────────────────────────────────
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

        // ── کی‌پد اعداد ۱–۹، Return، ۰، Info ────────────────────────────
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
                child: Text(n, style: const TextStyle(fontSize: 16)),
              ),
            RemoteButton(
              onTap: () => onPress('return'),
              child: const Icon(Icons.replay_rounded),
            ),
            RemoteButton(
              onTap: () => onPress('num_0'),
              child: const Text('0', style: TextStyle(fontSize: 16)),
            ),
            RemoteButton(
              onTap: () => onPress('info'),
              child: const Icon(Icons.info_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── NavPad دایره‌ای ──────────────────────────────────────────────
        _NavPad(onPress: onPress),
        const SizedBox(height: 16),

        // ── VOL / HOME / CH (ردیف بالا) ─────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                label: 'VOL',
                onTap: () => onPress('vol_up'),
                child: const Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                accent: accent.withOpacity(0.25),
                onTap: () => onPress('home'),
                child: const Icon(Icons.home_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                label: 'CH',
                onTap: () => onPress('ch_up'),
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── VOL− / MUTE / CH− (ردیف پایین) ─────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('vol_down'),
                child: const Text('−', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('mute'),
                child: const Icon(Icons.volume_off_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('ch_down'),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── ردیف MENU ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('back'),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('menu'),
                child: const Icon(Icons.menu_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('exit'),
                label: 'EXIT',
                shape: RemoteButtonShape.tiny,
                child: const Icon(Icons.logout_rounded, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── دکمه‌های رنگی (فقط IR — بلوتوث پیام «پشتیبانی نمی‌شود» می‌دهد) ──
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

        // ── ردیف رسانه: Rewind / Play-Pause / Forward ───────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('rewind'),
                child: const Icon(Icons.fast_rewind_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('play_pause'),
                child: const Icon(Icons.play_arrow_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('forward'),
                child: const Icon(Icons.fast_forward_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── ردیف: Record / EPG (فقط IR) ──────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('record'),
                child: const Icon(Icons.fiber_manual_record_rounded,
                    color: AppColors.danger),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'EPG',
                onTap: () => onPress('epg'),
                child: const Icon(Icons.grid_view_rounded, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
    final locked = !mode.supportsTouchpad;
    return ListView(
      children: [
        // ── Power ────────────────────────────────────────────────────────
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
        const SizedBox(height: 16),

        // ── NavPad ───────────────────────────────────────────────────────
        _NavPad(onPress: onPress),
        const SizedBox(height: 16),

        // ── Back / Home / Menu ───────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('back'),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                accent: accent.withOpacity(0.2),
                onTap: () => onPress('home'),
                child: const Icon(Icons.home_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('menu'),
                child: const Icon(Icons.menu_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Play-Pause / Source ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('play_pause'),
                child: const Icon(Icons.play_arrow_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('source'),
                child: const Icon(Icons.input_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Vol+ / CH+ ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                label: 'VOL',
                onTap: () => onPress('vol_up'),
                child: const Text('+',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                label: 'CH',
                onTap: () => onPress('ch_up'),
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Vol− / Mute / CH− ───────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('vol_down'),
                child: const Text('−',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('mute'),
                child: const Icon(Icons.volume_off_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('ch_down'),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── تاچ‌پد موس (فقط بلوتوث — با پروفایل HID موس واقعی) ───────────
        Touchpad(locked: locked),
        const SizedBox(height: 16),
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
                  border: Border.all(color: AppColors.line),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: _arrow(Icons.keyboard_arrow_up_rounded, () => onPress('up')),
            ),
            Positioned(
              bottom: 0,
              child: _arrow(Icons.keyboard_arrow_down_rounded, () => onPress('down')),
            ),
            Positioned(
              left: 0,
              child: _arrow(Icons.keyboard_arrow_left_rounded, () => onPress('left')),
            ),
            Positioned(
              right: 0,
              child: _arrow(Icons.keyboard_arrow_right_rounded, () => onPress('right')),
            ),
            SizedBox(
              width: 60,
              height: 60,
              child: RemoteButton(
                shape: RemoteButtonShape.round,
                onTap: () => onPress('ok'),
                child: const Text('OK',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) => SizedBox(
        width: 48,
        height: 48,
        child: RemoteButton(
          shape: RemoteButtonShape.round,
          onTap: onTap,
          child: Icon(icon),
        ),
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
