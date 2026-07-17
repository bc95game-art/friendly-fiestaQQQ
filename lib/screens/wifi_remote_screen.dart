import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/wifi_remote_service.dart';
import '../theme/colors.dart';
import '../widgets/touchpad.dart';

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteScreen — کنترل وای‌فای، سبک EShare
///
///  جریان کار:
///    • قطع: دکمه «اتصال خودکار» — IP گتوی شبکه شناسایی و اتصال برقرار
///    • وصل: تاچ‌پد بزرگ (مرکز) + دکمه‌های فشرده بالا/پایین مثل EShare
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteScreen extends StatefulWidget {
  const WifiRemoteScreen({super.key});
  @override
  State<WifiRemoteScreen> createState() => _WifiRemoteScreenState();
}

class _WifiRemoteScreenState extends State<WifiRemoteScreen> {
  final _svc = WifiRemoteService.instance;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '9000');

  late StreamSubscription<WifiConnState> _sub;
  WifiConnState _state = WifiConnState.disconnected;
  bool _showManual = false;      // آیا ورودی دستی IP نمایش داده شود

  @override
  void initState() {
    super.initState();
    _state = _svc.state;
    _sub = _svc.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    // پیش‌پر کردن IP احتمالی
    _svc.detectTvIp().then((ips) {
      if (mounted && ips.isNotEmpty) _ipCtrl.text = ips.first;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  // ── اتصال خودکار ──────────────────────────────────────────────────────
  Future<void> _autoConnect() async {
    FocusScope.of(context).unfocus();
    await _svc.autoConnect();
    _showError();
  }

  // ── اتصال دستی ────────────────────────────────────────────────────────
  Future<void> _manualConnect() async {
    FocusScope.of(context).unfocus();
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9000;
    await _svc.connect(ip, port: port);
    _showError();
  }

  void _showError() {
    if (_svc.lastError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger.withOpacity(0.92),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(_svc.lastError!,
            style: const TextStyle(fontSize: 13)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _state == WifiConnState.connected;
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: connected
              ? _RemoteView(key: const ValueKey('remote'), svc: _svc)
              : _ConnectView(
                  key: const ValueKey('connect'),
                  state: _state,
                  ipCtrl: _ipCtrl,
                  portCtrl: _portCtrl,
                  showManual: _showManual,
                  onAutoConnect: _autoConnect,
                  onManualConnect: _manualConnect,
                  onToggleManual: () =>
                      setState(() => _showManual = !_showManual),
                  onBack: () => Navigator.of(context).pop(),
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  صفحه اتصال
// ═══════════════════════════════════════════════════════════════════════
class _ConnectView extends StatelessWidget {
  const _ConnectView({
    super.key,
    required this.state,
    required this.ipCtrl,
    required this.portCtrl,
    required this.showManual,
    required this.onAutoConnect,
    required this.onManualConnect,
    required this.onToggleManual,
    required this.onBack,
  });

  final WifiConnState state;
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final bool showManual;
  final VoidCallback onAutoConnect;
  final VoidCallback onManualConnect;
  final VoidCallback onToggleManual;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final connecting = state == WifiConnState.connecting;
    return Column(
      children: [
        // ── نوار بالا ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.text1),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.panel,
                  padding: const EdgeInsets.all(10),
                ),
              ),
              const SizedBox(width: 12),
              const Text('کنترل وای‌فای',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1)),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // ── آیکون ─────────────────────────────────────────────
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: AppColors.wifiAccent.withOpacity(0.45),
                        width: 1.5),
                    color: AppColors.wifiAccentDim,
                  ),
                  child: const Icon(Icons.wifi_rounded,
                      color: AppColors.wifiAccent, size: 42),
                ),
                const SizedBox(height: 20),

                const Text('کنترل از طریق وای‌فای تلویزیون',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1)),
                const SizedBox(height: 10),
                const Text(
                  'ابتدا گوشی را به WiFi تلویزیون وصل کنید،\n'
                  'سپس دکمه اتصال خودکار را بزنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.9, color: AppColors.text2),
                ),
                const SizedBox(height: 36),

                // ── دکمه اتصال خودکار ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: connecting ? null : onAutoConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.wifiAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    child: connecting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_find_rounded, size: 22),
                              SizedBox(width: 10),
                              Text('اتصال خودکار'),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── تبدیل به دستی ─────────────────────────────────────
                TextButton(
                  onPressed: onToggleManual,
                  child: Text(
                    showManual ? 'پنهان کردن تنظیمات دستی' : 'تنظیم دستی IP و پورت',
                    style: const TextStyle(
                        color: AppColors.text3, fontSize: 13),
                  ),
                ),

                // ── ورودی دستی ────────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: showManual
                      ? Column(
                          children: [
                            const SizedBox(height: 4),
                            _IpField(ctrl: ipCtrl, label: 'آدرس IP'),
                            const SizedBox(height: 10),
                            _IpField(
                                ctrl: portCtrl,
                                label: 'پورت',
                                keyboardType: TextInputType.number),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: connecting ? null : onManualConnect,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.wifiAccent,
                                  side: const BorderSide(
                                      color: AppColors.wifiAccent),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                child: const Text('اتصال دستی',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 36),
                // ── راهنما ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.wifiAccent, size: 16),
                        SizedBox(width: 8),
                        Text('نحوه اتصال',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text1)),
                      ]),
                      SizedBox(height: 12),
                      _HintRow(
                          n: '۱',
                          text:
                              'تنظیمات تلویزیون را باز کنید و WiFi Hotspot یا نقطه اتصال را روشن کنید'),
                      _HintRow(
                          n: '۲',
                          text:
                              'در گوشی، به WiFi تلویزیون وصل شوید (نامش روی صفحه نمایش است)'),
                      _HintRow(
                          n: '۳',
                          text:
                              'به این صفحه برگردید و «اتصال خودکار» را بزنید'),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IpField extends StatelessWidget {
  const _IpField(
      {required this.ctrl,
      required this.label,
      this.keyboardType = TextInputType.url});
  final TextEditingController ctrl;
  final String label;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.text1, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.panel,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                const BorderSide(color: AppColors.wifiAccent, width: 1.8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.n, required this.text});
  final String n;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.wifiAccent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(n,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.wifiAccent,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    height: 1.7))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  صفحه ریموت (وقتی وصل است) — سبک EShare
// ═══════════════════════════════════════════════════════════════════════
class _RemoteView extends StatefulWidget {
  const _RemoteView({super.key, required this.svc});
  final WifiRemoteService svc;
  @override
  State<_RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<_RemoteView> {
  bool _showExtra = false; // پنل کنترل‌های بیشتر

  Future<void> _k(String key) async {
    HapticFeedback.lightImpact();
    await widget.svc.sendKey(key);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Column(
      children: [
        // ══ نوار بالا ══════════════════════════════════════════════════
        _TopBar(
          ip: widget.svc.connectedIp ?? '',
          port: widget.svc.connectedPort,
          onDisconnect: () async {
            await widget.svc.disconnect();
          },
          onToggleExtra: () => setState(() => _showExtra = !_showExtra),
          showExtra: _showExtra,
        ),

        // ══ ردیف بالای تاچ‌پد: Back / Home / Menu ═════════════════════
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _PillBtn(
                  icon: Icons.arrow_back_rounded,
                  label: 'بازگشت',
                  onTap: () => _k('back')),
              const SizedBox(width: 8),
              _PillBtn(
                  icon: Icons.home_rounded,
                  label: 'خانه',
                  onTap: () => _k('home'),
                  accent: AppColors.wifiAccent),
              const SizedBox(width: 8),
              _PillBtn(
                  icon: Icons.menu_rounded,
                  label: 'منو',
                  onTap: () => _k('menu')),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ══ تاچ‌پد اصلی — بزرگ، مثل EShare ═══════════════════════════
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Touchpad(
              active: true,
              accentColor: AppColors.wifiAccent,
              height: double.infinity,
              onMove: (dx, dy) => widget.svc.sendMouseMove(dx, dy),
              onTap: () => widget.svc.sendMouseClick(),
              // آرامش اسکرول: Column ندارد ListView، پس قفل scroll لازم نیست
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ══ ردیف پایین: Vol- / Mute / Vol+ ════════════════════════════
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _PillBtn(
                  icon: Icons.volume_down_rounded,
                  label: 'صدا —',
                  onTap: () => _k('vol_down')),
              const SizedBox(width: 8),
              _PillBtn(
                  icon: Icons.volume_mute_rounded,
                  label: 'بی‌صدا',
                  onTap: () => _k('mute')),
              const SizedBox(width: 8),
              _PillBtn(
                  icon: Icons.volume_up_rounded,
                  label: 'صدا +',
                  onTap: () => _k('vol_up')),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ══ پنل کنترل‌های بیشتر (قابل جمع) ═══════════════════════════
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          child: _showExtra
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: _ExtraPanel(onKey: _k),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ── نوار بالای ریموت ──────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.ip,
    required this.port,
    required this.onDisconnect,
    required this.onToggleExtra,
    required this.showExtra,
  });
  final String ip;
  final int? port;
  final VoidCallback onDisconnect;
  final VoidCallback onToggleExtra;
  final bool showExtra;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // وضعیت
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.wifiAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: AppColors.wifiAccent.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.wifiAccent)),
              const SizedBox(width: 6),
              Text('$ip${port != null ? ':$port' : ''}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.wifiAccent,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const Spacer(),
          // دکمه کنترل‌های بیشتر
          IconButton(
            onPressed: onToggleExtra,
            tooltip: 'دکمه‌های بیشتر',
            icon: AnimatedRotation(
              turns: showExtra ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(Icons.keyboard_arrow_up_rounded,
                  color: AppColors.text2),
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.panel,
              padding: const EdgeInsets.all(9),
            ),
          ),
          const SizedBox(width: 8),
          // قطع اتصال
          IconButton(
            onPressed: onDisconnect,
            tooltip: 'قطع اتصال',
            icon: const Icon(Icons.wifi_off_rounded,
                color: AppColors.danger, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.danger.withOpacity(0.1),
              padding: const EdgeInsets.all(9),
            ),
          ),
        ],
      ),
    );
  }
}

// ── پنل دکمه‌های بیشتر (Power، NavPad، CH، Source، Play) ──────────────
class _ExtraPanel extends StatelessWidget {
  const _ExtraPanel({required this.onKey});
  final Future<void> Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          // Power + Source + Play
          Row(children: [
            _XBtn(Icons.power_settings_new_rounded, 'پاور',
                () => onKey('power'), AppColors.danger),
            const SizedBox(width: 8),
            _XBtn(Icons.input_rounded, 'ورودی', () => onKey('source'),
                AppColors.wifiAccent),
            const SizedBox(width: 8),
            _XBtn(Icons.play_circle_rounded, 'پخش',
                () => onKey('play_pause'), AppColors.wifiAccent),
          ]),
          const SizedBox(height: 10),
          // NavPad کوچک
          _MiniNavPad(onKey: onKey),
          const SizedBox(height: 10),
          // CH
          Row(children: [
            _XBtn(Icons.keyboard_arrow_up_rounded, 'کانال +',
                () => onKey('ch_up'), null),
            const SizedBox(width: 8),
            _XBtn(Icons.keyboard_arrow_down_rounded, 'کانال —',
                () => onKey('ch_down'), null),
            const SizedBox(width: 8),
            _XBtn(Icons.fast_rewind_rounded, 'عقب',
                () => onKey('rewind'), null),
            const SizedBox(width: 8),
            _XBtn(Icons.fast_forward_rounded, 'جلو',
                () => onKey('forward'), null),
          ]),
        ],
      ),
    );
  }
}

class _MiniNavPad extends StatelessWidget {
  const _MiniNavPad({required this.onKey});
  final Future<void> Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    const s = 44.0;
    const ok = 50.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          _NavDot(Icons.keyboard_arrow_up_rounded, () => onKey('up'), s),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _NavDot(Icons.keyboard_arrow_left_rounded, () => onKey('left'), s),
            const SizedBox(width: 3),
            _NavDot(Icons.radio_button_checked_rounded, () => onKey('ok'), ok,
                AppColors.wifiAccent),
            const SizedBox(width: 3),
            _NavDot(Icons.keyboard_arrow_right_rounded,
                () => onKey('right'), s),
          ]),
          _NavDot(Icons.keyboard_arrow_down_rounded, () => onKey('down'), s),
        ]),
      ],
    );
  }
}

class _NavDot extends StatelessWidget {
  const _NavDot(this.icon, this.onTap, this.size, [this.accent]);
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent != null
              ? accent!.withOpacity(0.15)
              : AppColors.panel2,
          border: Border.all(
              color: accent != null
                  ? accent!.withOpacity(0.45)
                  : AppColors.line),
        ),
        child: Icon(icon, size: size * 0.42,
            color: accent ?? AppColors.text1),
      ),
    );
  }
}

class _XBtn extends StatelessWidget {
  const _XBtn(this.icon, this.label, this.onTap, this.accent);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final c = accent ?? AppColors.text2;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: accent != null ? accent!.withOpacity(0.1) : AppColors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: accent != null
                    ? accent!.withOpacity(0.35)
                    : AppColors.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: c.withOpacity(0.9),
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ── دکمه pill پایین/بالا تاچ‌پد ──────────────────────────────────────
class _PillBtn extends StatelessWidget {
  const _PillBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? AppColors.text2;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: accent != null ? accent!.withOpacity(0.1) : AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent != null
                  ? accent!.withOpacity(0.4)
                  : AppColors.line,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: c.withOpacity(0.85),
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
