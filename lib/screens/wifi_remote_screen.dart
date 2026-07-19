import 'dart:async';
import 'package:flutter/material.dart';
import '../models/remote_mode.dart';
import '../services/wifi_remote_service.dart';
import '../theme/colors.dart';
import 'size_picker_screen.dart';

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteScreen — کنترل وای‌فای، پروتکل EShare دقیق
///
///  روش اتصال صحیح (مثل EShare):
///    ۱. hotspot گوشی را روشن کنید
///    ۲. تلویزیون را به hotspot گوشی وصل کنید
///    ۳. دکمه «اتصال خودکار» را بزنید
///
///  پس از اتصال موفق، کاربر به صفحه‌ی انتخاب نوع کنترل (بزرگ/کوچک)
///  هدایت می‌شود — دقیقاً مثل بخش‌های بلوتوث و فرستنده.
///
///  پروتکل: TCP پورت 2012 — همان پروتکل دقیق EShare Server
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteScreen extends StatefulWidget {
  const WifiRemoteScreen({super.key});
  @override
  State<WifiRemoteScreen> createState() => _WifiRemoteScreenState();
}

class _WifiRemoteScreenState extends State<WifiRemoteScreen> {
  final _svc = WifiRemoteService.instance;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(
      text: WifiRemoteService.defaultPort.toString());

  late StreamSubscription<WifiConnState> _sub;
  WifiConnState _state = WifiConnState.disconnected;
  bool _showManual = false;

  /// جلوگیری از navigate مجدد وقتی کاربر Back می‌زند و برمی‌گردد.
  /// وقتی قطع می‌شود، reset می‌شود تا اتصال بعدی دوباره navigate کند.
  bool _navigatedToRemote = false;

  @override
  void initState() {
    super.initState();
    _state = _svc.state;
    // اگر از قبل وصل بود (کاربر Back زد و برگشت)، پرچم بزن تا دوباره
    // navigate نشود — کاربر خودش باید دکمه «انتخاب نوع کنترل» را بزند.
    if (_state == WifiConnState.connected) _navigatedToRemote = true;

    _sub = _svc.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s == WifiConnState.connected && !_navigatedToRemote) {
        // اتصال جدید برقرار شد — به انتخاب کنترل برو
        _navigatedToRemote = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _pushSizePicker());
      }
      if (s == WifiConnState.disconnected || s == WifiConnState.error) {
        // اتصال قطع شد — پرچم reset می‌شود تا اتصال بعدی navigate کند
        _navigatedToRemote = false;
      }
    });
  }

  /// navigate به SizePickerScreen با mode=wifi
  void _pushSizePicker() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SizePickerScreen(mode: RemoteMode.wifi),
      ),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    FocusScope.of(context).unfocus();
    await _svc.autoConnect();
    _showError();
  }

  Future<void> _manualConnect() async {
    FocusScope.of(context).unfocus();
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ??
        WifiRemoteService.defaultPort;
    await _svc.connect(ip, port: port);
    _showError();
  }

  void _showError() {
    if (_svc.lastError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger.withOpacity(0.92),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(_svc.lastError!,
            style: const TextStyle(fontSize: 13, height: 1.6)),
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
          // وقتی متصل است و کاربر برگشته، _ConnectedView نشان داده می‌شود
          // وقتی متصل است و هنوز navigate نشده، لحظه‌ای _ConnectedView نشان
          // داده می‌شود قبل از اینکه navigate اتفاق بیفتد (postFrameCallback)
          child: connected
              ? _ConnectedView(
                  key: const ValueKey('connected'),
                  ip: _svc.connectedIp ?? '',
                  onEnter: _pushSizePicker,
                  onDisconnect: () async {
                    await _svc.disconnect();
                    setState(() => _navigatedToRemote = false);
                  },
                )
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
//  صفحه «متصل است» — وقتی کاربر از SizePicker برمی‌گردد
// ═══════════════════════════════════════════════════════════════════════
class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    super.key,
    required this.ip,
    required this.onEnter,
    required this.onDisconnect,
  });
  final String ip;
  final VoidCallback onEnter;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── آیکون متصل ───────────────────────────────────────────────
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: AppColors.wifiAccent.withOpacity(0.45), width: 1.5),
              color: AppColors.wifiAccentDim,
            ),
            child: const Icon(Icons.wifi_rounded,
                color: AppColors.wifiAccent, size: 42),
          ),
          const SizedBox(height: 20),

          const Text('متصل به تلویزیون',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text1)),
          const SizedBox(height: 8),

          // ── نشانگر IP ──────────────────────────────────────────────
          if (ip.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.wifiAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: AppColors.wifiAccent.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.wifiAccent)),
                const SizedBox(width: 6),
                Text(ip,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.wifiAccent,
                        fontWeight: FontWeight.w600)),
              ]),
            ),

          const SizedBox(height: 40),

          // ── دکمه «انتخاب نوع کنترل» ───────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onEnter,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.wifiAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 22),
                  SizedBox(width: 10),
                  Text('انتخاب نوع کنترل'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── دکمه قطع اتصال ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDisconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('قطع اتصال',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
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
        // ── نوار بالا ──────────────────────────────────────────────────
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

                const Text('کنترل تلویزیون از طریق وای‌فای',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1)),
                const SizedBox(height: 10),
                const Text(
                  'hotspot گوشی را روشن کنید، تلویزیون را به آن وصل کنید\n'
                  'سپس «اتصال خودکار» را بزنید — تلویزیون پیدا می‌شود',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.9, color: AppColors.text2),
                ),
                const SizedBox(height: 36),

                // ── دکمه اتصال خودکار ──────────────────────────────────
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

                // ── ورودی دستی ────────────────────────────────────────
                TextButton(
                  onPressed: onToggleManual,
                  child: Text(
                    showManual
                        ? 'پنهان کردن تنظیمات دستی'
                        : 'وارد کردن IP تلویزیون به‌صورت دستی',
                    style: const TextStyle(
                        color: AppColors.text3, fontSize: 13),
                  ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: showManual
                      ? Column(
                          children: [
                            const SizedBox(height: 4),
                            _IpField(
                                ctrl: ipCtrl,
                                label: 'آدرس IP تلویزیون (مثال: 192.168.1.10)',
                                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                            const SizedBox(height: 10),
                            _IpField(
                                ctrl: portCtrl,
                                label: 'پورت (پیش‌فرض: 2012)',
                                keyboardType: TextInputType.number),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed:
                                    connecting ? null : onManualConnect,
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

                // ── راهنمای اتصال ─────────────────────────────────────
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
                        text: 'hotspot گوشی را روشن کنید (تنظیمات → نقطه اتصال)',
                      ),
                      _HintRow(
                        n: '۲',
                        text: 'در تلویزیون، WiFi را به hotspot گوشی وصل کنید',
                      ),
                      _HintRow(
                        n: '۳',
                        text: 'دکمه «اتصال خودکار» را بزنید — برنامه تلویزیون را پیدا می‌کند',
                      ),
                      _HintRow(
                        n: '۴',
                        text: 'روش جایگزین: هر دو را به یک WiFi وصل کنید و اتصال خودکار بزنید',
                      ),
                      _HintRow(
                        n: '۵',
                        text: 'اگر پیدا نشد: IP تلویزیون را از تنظیمات شبکه آن بگیرید و دستی وارد کنید',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── نکته پروتکل ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.wifiAccent.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.wifiAccent.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.settings_ethernet_rounded,
                          color: AppColors.wifiAccent, size: 15),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'پروتکل EShare — پورت 2012 — سازگار با EShare Server',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.wifiAccent,
                              height: 1.5),
                        ),
                      ),
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
        labelStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
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
                    fontSize: 12, color: AppColors.text2, height: 1.7))),
      ]),
    );
  }
}
