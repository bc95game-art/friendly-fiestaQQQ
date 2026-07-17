import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/remote_mode.dart';
import '../services/wifi_remote_service.dart';
import '../theme/colors.dart';
import '../widgets/touchpad.dart';

/// ══════════════════════════════════════════════════════════════════════
///  WiFi Remote Screen
///  صفحه کنترل تلویزیون از طریق وای‌فای محلی
///
///  جریان کار:
///    ۱. وقتی قطع است: پنل اتصال نمایش داده می‌شود (IP + کشف خودکار)
///    ۲. وقتی وصل است: ریموت اصلی با دکمه‌های تمیز + تاچ‌پد EShare-style
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteScreen extends StatefulWidget {
  const WifiRemoteScreen({super.key});

  @override
  State<WifiRemoteScreen> createState() => _WifiRemoteScreenState();
}

class _WifiRemoteScreenState extends State<WifiRemoteScreen>
    with TickerProviderStateMixin {
  final _svc = WifiRemoteService.instance;
  final _ipCtrl = TextEditingController(text: '192.168.1.');
  final _ipFocus = FocusNode();

  late StreamSubscription<WifiConnState> _connSub;
  WifiConnState _connState = WifiConnState.disconnected;

  bool _discovering = false;
  List<String> _found = [];

  // اندازه: کوچک یا بزرگ
  bool _isSmall = true;

  late final AnimationController _cardCtrl;
  late final Animation<double> _cardAnim;

  @override
  void initState() {
    super.initState();
    _connState = _svc.state;
    _connSub = _svc.stateStream.listen((s) {
      if (mounted) setState(() => _connState = s);
    });

    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _cardAnim =
        CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _connSub.cancel();
    _ipCtrl.dispose();
    _ipFocus.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  // ── اتصال ─────────────────────────────────────────────────────────────
  Future<void> _connect() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    _ipFocus.unfocus();
    await _svc.connect(ip);
    if (_svc.lastError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger.withOpacity(0.9),
        content: Text(_svc.lastError!),
      ));
    }
  }

  // ── کشف خودکار ────────────────────────────────────────────────────────
  Future<void> _discover() async {
    setState(() {
      _discovering = true;
      _found = [];
    });
    final result = await _svc.discover();
    if (mounted) {
      setState(() {
        _discovering = false;
        _found = result;
      });
      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تلویزیونی پیدا نشد — IP را دستی وارد کنید'),
        ));
      }
    }
  }

  // ── ارسال دکمه ────────────────────────────────────────────────────────
  Future<void> _key(String k) async {
    HapticFeedback.lightImpact();
    await _svc.sendKey(k);
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connState == WifiConnState.connected;
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Column(
          children: [
            // ── نوار بالا ─────────────────────────────────────────────
            _AppBar(
              connected: connected,
              ip: _svc.connectedIp,
              isSmall: _isSmall,
              onBack: () async {
                await _svc.disconnect();
                if (mounted) Navigator.of(context).pop();
              },
              onToggleSize: connected
                  ? () => setState(() => _isSmall = !_isSmall)
                  : null,
            ),

            // ── بدنه ──────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: connected
                    ? _RemoteBody(
                        key: ValueKey(_isSmall),
                        isSmall: _isSmall,
                        svc: _svc,
                        onKey: _key,
                      )
                    : _SetupPanel(
                        key: const ValueKey('setup'),
                        ipCtrl: _ipCtrl,
                        ipFocus: _ipFocus,
                        state: _connState,
                        discovering: _discovering,
                        found: _found,
                        onConnect: _connect,
                        onDiscover: _discover,
                        onSelectIp: (ip) {
                          _ipCtrl.text = ip;
                          _connect();
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  نوار بالای صفحه
// ═══════════════════════════════════════════════════════════════════════
class _AppBar extends StatelessWidget {
  const _AppBar({
    required this.connected,
    required this.ip,
    required this.isSmall,
    required this.onBack,
    required this.onToggleSize,
  });

  final bool connected;
  final String? ip;
  final bool isSmall;
  final VoidCallback onBack;
  final VoidCallback? onToggleSize;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('کنترل وای‌فای',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: connected
                      ? Text(ip ?? '',
                          key: ValueKey(ip),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.wifiAccent))
                      : const Text('وصل نشده',
                          key: ValueKey('off'),
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text3)),
                ),
              ],
            ),
          ),
          // نشانگر وضعیت
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: connected
                  ? AppColors.wifiAccent.withOpacity(0.15)
                  : AppColors.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: connected
                    ? AppColors.wifiAccent.withOpacity(0.5)
                    : AppColors.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        connected ? AppColors.wifiAccent : AppColors.text3,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  connected ? 'متصل' : 'قطع',
                  style: TextStyle(
                      fontSize: 11,
                      color: connected
                          ? AppColors.wifiAccent
                          : AppColors.text3),
                ),
              ],
            ),
          ),
          if (connected && onToggleSize != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onToggleSize,
              icon: Icon(
                isSmall
                    ? Icons.open_in_full_rounded
                    : Icons.close_fullscreen_rounded,
                color: AppColors.text2,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.panel,
                padding: const EdgeInsets.all(9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  پنل راه‌اندازی (وقتی هنوز وصل نشده)
// ═══════════════════════════════════════════════════════════════════════
class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    super.key,
    required this.ipCtrl,
    required this.ipFocus,
    required this.state,
    required this.discovering,
    required this.found,
    required this.onConnect,
    required this.onDiscover,
    required this.onSelectIp,
  });

  final TextEditingController ipCtrl;
  final FocusNode ipFocus;
  final WifiConnState state;
  final bool discovering;
  final List<String> found;
  final VoidCallback onConnect;
  final VoidCallback onDiscover;
  final void Function(String) onSelectIp;

  @override
  Widget build(BuildContext context) {
    final connecting = state == WifiConnState.connecting;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // آیکون وسط
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppColors.wifiAccent.withOpacity(0.4)),
              color: AppColors.wifiAccentDim,
            ),
            child: const Icon(Icons.wifi_rounded,
                color: AppColors.wifiAccent, size: 38),
          ),
          const SizedBox(height: 20),
          const Text(
            'آدرس IP تلویزیون',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text1),
          ),
          const SizedBox(height: 8),
          const Text(
            'گوشی و تلویزیون باید روی یک وای‌فای باشند\n'
            'سرور ریموت روی پورت ۹۰۰۰ باید روی TV اجرا باشد',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, height: 1.8, color: AppColors.text3),
          ),
          const SizedBox(height: 28),

          // ── ورودی IP ──────────────────────────────────────────────
          TextField(
            controller: ipCtrl,
            focusNode: ipFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style:
                const TextStyle(color: AppColors.text1, fontSize: 16),
            decoration: InputDecoration(
              hintText: '192.168.1.XXX',
              hintStyle:
                  const TextStyle(color: AppColors.text3, fontSize: 16),
              filled: true,
              fillColor: AppColors.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.wifiAccent, width: 2),
              ),
              prefixIcon: const Icon(Icons.lan_rounded,
                  color: AppColors.wifiAccent),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
            onSubmitted: (_) => onConnect(),
          ),
          const SizedBox(height: 12),

          // ── دکمه اتصال ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: connecting ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.wifiAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: connecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('اتصال'),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // ── کشف خودکار ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: discovering ? null : onDiscover,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.wifiAccent,
                side: BorderSide(
                    color: AppColors.wifiAccent.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: discovering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.wifiAccent,
                      ))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('جستجوی خودکار در شبکه'),
                      ],
                    ),
            ),
          ),

          // ── نتایج کشف ─────────────────────────────────────────────
          if (found.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('دستگاه‌های یافت‌شده:',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.text2)),
            ),
            const SizedBox(height: 8),
            ...found.map((ip) => _FoundDeviceTile(
                ip: ip, onTap: () => onSelectIp(ip))),
          ],

          // ── راهنمای سرور ──────────────────────────────────────────
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.wifiAccent, size: 16),
                    SizedBox(width: 8),
                    Text('راه‌اندازی سرور روی تلویزیون',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text1)),
                  ],
                ),
                const SizedBox(height: 10),
                _HelpStep(n: '۱', text: 'Termux را روی تلویزیون نصب کنید'),
                _HelpStep(n: '۲', text: 'دستور   python3 tv_server.py   را اجرا کنید'),
                _HelpStep(n: '۳', text: 'IP تلویزیون را از طریق تنظیمات شبکه بیابید'),
                const SizedBox(height: 8),
                const Text(
                    'فایل tv_server.py در README پروژه موجود است',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FoundDeviceTile extends StatelessWidget {
  const _FoundDeviceTile({required this.ip, required this.onTap});
  final String ip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.wifiAccentDim,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.wifiAccent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.tv_rounded,
                color: AppColors.wifiAccent, size: 18),
            const SizedBox(width: 12),
            Text(ip,
                style: const TextStyle(
                    color: AppColors.text1,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            const Text('اتصال',
                style: TextStyle(
                    color: AppColors.wifiAccent, fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left,
                color: AppColors.wifiAccent, size: 16),
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.n, required this.text});
  final String n;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.wifiAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(n,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.wifiAccent,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.text2, height: 1.6))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  بدنه ریموت وقتی وصل است
// ═══════════════════════════════════════════════════════════════════════
class _RemoteBody extends StatefulWidget {
  const _RemoteBody({
    super.key,
    required this.isSmall,
    required this.svc,
    required this.onKey,
  });

  final bool isSmall;
  final WifiRemoteService svc;
  final Future<void> Function(String) onKey;

  @override
  State<_RemoteBody> createState() => _RemoteBodyState();
}

class _RemoteBodyState extends State<_RemoteBody> {
  final _scrollCtrl = ScrollController();
  bool _scrollLocked = false;

  void _lockScroll() => setState(() => _scrollLocked = true);
  void _unlockScroll() => setState(() => _scrollLocked = false);

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollCtrl,
      physics: _scrollLocked
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: widget.isSmall
            ? _buildSmall()
            : _buildLarge(),
      ),
    );
  }

  // ── حالت کوچک: تاچ‌پد محوری + دکمه‌های ضروری ─────────────────────
  List<Widget> _buildSmall() {
    return [
      _buildTopRow(),
      const SizedBox(height: 16),
      _buildNavPad(),
      const SizedBox(height: 16),
      _buildSystemRow(),
      const SizedBox(height: 14),
      _buildVolRow(),
      const SizedBox(height: 14),
      _buildMediaRow(),
      const SizedBox(height: 20),
      _buildTouchpad(),
      const SizedBox(height: 20),
    ];
  }

  // ── حالت بزرگ: بیشتر ─────────────────────────────────────────────
  List<Widget> _buildLarge() {
    return [
      _buildTopRow(),
      const SizedBox(height: 16),
      _buildNavPad(),
      const SizedBox(height: 16),
      _buildSystemRow(),
      const SizedBox(height: 14),
      _buildVolRow(),
      const SizedBox(height: 14),
      _buildChRow(),
      const SizedBox(height: 14),
      _buildMediaRow(),
      const SizedBox(height: 14),
      _buildFullMediaRow(),
      const SizedBox(height: 20),
      _buildTouchpad(height: 220),
      const SizedBox(height: 20),
    ];
  }

  // ── ردیف بالا: Power + Source ─────────────────────────────────────
  Widget _buildTopRow() {
    return Row(
      children: [
        Expanded(
          child: _RBtn(
            icon: Icons.power_settings_new_rounded,
            label: 'پاور',
            color: AppColors.danger,
            onTap: () => widget.onKey('power'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RBtn(
            icon: Icons.input_rounded,
            label: 'ورودی',
            color: AppColors.wifiAccent,
            onTap: () => widget.onKey('source'),
          ),
        ),
      ],
    );
  }

  // ── NavPad ────────────────────────────────────────────────────────
  Widget _buildNavPad() {
    return _NavPad(onKey: widget.onKey);
  }

  // ── ردیف سیستم: Back / Home / Menu ───────────────────────────────
  Widget _buildSystemRow() {
    return Row(
      children: [
        Expanded(
            child: _RBtn(
                icon: Icons.arrow_back_rounded,
                label: 'بازگشت',
                onTap: () => widget.onKey('back'))),
        const SizedBox(width: 8),
        Expanded(
            child: _RBtn(
                icon: Icons.home_rounded,
                label: 'خانه',
                onTap: () => widget.onKey('home'))),
        const SizedBox(width: 8),
        Expanded(
            child: _RBtn(
                icon: Icons.menu_rounded,
                label: 'منو',
                onTap: () => widget.onKey('menu'))),
      ],
    );
  }

  // ── ردیف صدا ─────────────────────────────────────────────────────
  Widget _buildVolRow() {
    return _LabeledRow(
      label: 'صدا',
      children: [
        _RBtn(
            icon: Icons.volume_down_rounded,
            label: '—',
            onTap: () => widget.onKey('vol_down')),
        _RBtn(
            icon: Icons.volume_mute_rounded,
            label: 'بی‌صدا',
            color: AppColors.text2,
            onTap: () => widget.onKey('mute')),
        _RBtn(
            icon: Icons.volume_up_rounded,
            label: '+',
            onTap: () => widget.onKey('vol_up')),
      ],
    );
  }

  // ── ردیف کانال ───────────────────────────────────────────────────
  Widget _buildChRow() {
    return _LabeledRow(
      label: 'کانال',
      children: [
        _RBtn(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'قبلی',
            onTap: () => widget.onKey('ch_down')),
        _RBtn(
            icon: Icons.tv_rounded,
            label: 'TV',
            onTap: () => widget.onKey('source')),
        _RBtn(
            icon: Icons.keyboard_arrow_up_rounded,
            label: 'بعدی',
            onTap: () => widget.onKey('ch_up')),
      ],
    );
  }

  // ── ردیف پخش ─────────────────────────────────────────────────────
  Widget _buildMediaRow() {
    return Row(
      children: [
        Expanded(
            child: _RBtn(
                icon: Icons.play_circle_rounded,
                label: 'پخش/توقف',
                color: AppColors.wifiAccent,
                onTap: () => widget.onKey('play_pause'))),
      ],
    );
  }

  // ── ردیف مدیا کامل ───────────────────────────────────────────────
  Widget _buildFullMediaRow() {
    return Row(
      children: [
        Expanded(
            child: _RBtn(
                icon: Icons.fast_rewind_rounded,
                label: 'عقب',
                onTap: () => widget.onKey('rewind'))),
        const SizedBox(width: 8),
        Expanded(
            child: _RBtn(
                icon: Icons.play_circle_rounded,
                label: 'پخش',
                color: AppColors.wifiAccent,
                onTap: () => widget.onKey('play_pause'))),
        const SizedBox(width: 8),
        Expanded(
            child: _RBtn(
                icon: Icons.fast_forward_rounded,
                label: 'جلو',
                onTap: () => widget.onKey('forward'))),
      ],
    );
  }

  // ── تاچ‌پد EShare-style (همیشه فعال) ─────────────────────────────
  Widget _buildTouchpad({double height = 180}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4, bottom: 8),
          child: Text('تاچ‌پد موس',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
        ),
        Touchpad(
          active: true, // همیشه فعال در وای‌فای
          accentColor: AppColors.wifiAccent,
          height: height,
          onMove: (dx, dy) => widget.svc.sendMouseMove(dx, dy),
          onTap: () => widget.svc.sendMouseClick(),
          onDragStart: _lockScroll,
          onDragEnd: _unlockScroll,
        ),
      ],
    );
  }
}

// ── ناوپد جهت‌دار ──────────────────────────────────────────────────────
class _NavPad extends StatelessWidget {
  const _NavPad({required this.onKey});
  final Future<void> Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    const s = 52.0;
    const ok = 60.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavBtn(icon: Icons.keyboard_arrow_up_rounded, onTap: () => onKey('up'), size: s),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavBtn(icon: Icons.keyboard_arrow_left_rounded, onTap: () => onKey('left'), size: s),
            const SizedBox(width: 4),
            _NavBtn(icon: Icons.radio_button_checked_rounded, onTap: () => onKey('ok'), size: ok,
                accent: AppColors.wifiAccent),
            const SizedBox(width: 4),
            _NavBtn(icon: Icons.keyboard_arrow_right_rounded, onTap: () => onKey('right'), size: s),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavBtn(icon: Icons.keyboard_arrow_down_rounded, onTap: () => onKey('down'), size: s),
          ],
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.onTap,
    required this.size,
    this.accent,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.text1;
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
              ? accent!.withOpacity(0.18)
              : AppColors.panel,
          border: Border.all(
            color: accent != null
                ? accent!.withOpacity(0.5)
                : AppColors.line,
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: color, size: size * 0.42),
      ),
    );
  }
}

// ── دکمه ریموت استاندارد ──────────────────────────────────────────────
class _RBtn extends StatelessWidget {
  const _RBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text1;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color != null ? c.withOpacity(0.12) : AppColors.panel,
          border: Border.all(
              color: color != null
                  ? c.withOpacity(0.4)
                  : AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: c.withOpacity(0.8),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── ردیف با برچسب کنار ────────────────────────────────────────────────
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.text3),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        ...children.map((c) => Expanded(child: c)).toList().fold<List<Widget>>(
            [],
            (list, item) =>
                list.isEmpty ? [item] : [...list, const SizedBox(width: 8), item]),
      ],
    );
  }
}
