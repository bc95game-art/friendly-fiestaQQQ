import 'dart:async';
import 'package:flutter/material.dart';

import '../models/remote_mode.dart';
import '../services/bt_hid_service.dart';
import '../services/permissions_service.dart';
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

class _RemoteScreenState extends State<RemoteScreen> with WidgetsBindingObserver {
  late final RemoteController _controller = RemoteController(widget.mode);
  // ⚠️ رفع باگ: قبلاً همیشه از «قطع» شروع می‌شد حتی اگر اتصال بلوتوث از
  // قبل (مثلاً از صفحه‌ی قبلی) واقعاً برقرار بود — وضعیت واقعی سرویس را
  // همان لحظه می‌خوانیم تا نمایش با واقعیت هم‌خوان باشد.
  BtConnState _btState = BtHidService.instance.state;
  StreamSubscription<BtConnState>? _btSub;

  // ── تلاش خودکار مجدد وقتی اتصال بدون اقدام کاربر قطع می‌شود ──────────
  // رفع باگ «قطع تصادفی/نیاز به ری‌استارت اپ»: به‌جای منتظر ماندن برای
  // برگشت اپ از پس‌زمینه یا لمس دستی، با کمی تاخیر (و افزایش تدریجی تاخیر)
  // خودش دوباره تلاش می‌کند؛ بعد از چند شکست پیاپی، یک ریست کامل ثبت HID
  // امتحان می‌شود (دقیقاً کاری که قبلاً فقط ری‌استارت اپ انجام می‌داد).
  Timer? _retryTimer;
  int _reconnectAttempts = 0;
  static const _maxAutoRetries = 5;

  // ── دیباونس: جلوگیری از ارسال چند فرمان همزمان هنگام ضربه‌های سریع ──
  DateTime? _lastPressTime;

  // ── جلوگیری از اسپم پیام‌های خطا: هر خطای یکسان فقط یک بار به‌صورت
  // دیالوگ (نه SnackBar تکرارشونده) نشان داده می‌شود.
  String? _lastErrorShown;
  DateTime? _lastErrorAt;
  bool _errorDialogOpen = false;

  // ── تشخیص «نوسان اتصال»: وقتی وضعیت چند بار پشت‌سرهم بین در-حال-اتصال
  // و قطع‌شده نوسان می‌کند (یعنی تلویزیون اتصالی که گوشی شروع کرده را رد
  // می‌کند)، به‌جای تکرار بی‌نتیجه، روش جایگزین (قابل‌مشاهده کردن گوشی) را
  // پیشنهاد می‌دهیم.
  int _connectingBounces = 0;
  bool _showAlternativeHint = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode.isBluetooth) {
      WidgetsBinding.instance.addObserver(this);
      _btSub = BtHidService.instance.stateStream.listen((s) {
        if (!mounted) return;
        final wasConnected = _btState == BtConnState.connected;
        setState(() {
          if (s == BtConnState.connecting) {
            _connectingBounces++;
          } else if (s == BtConnState.connected) {
            _connectingBounces = 0;
            _showAlternativeHint = false;
            _reconnectAttempts = 0;
          }
          if (_connectingBounces >= 3 &&
              (s == BtConnState.disconnected || s == BtConnState.error)) {
            _showAlternativeHint = true;
          }
          _btState = s;
        });
        // اتصال بدون دخالت کاربر قطع شد (نه اینکه کاربر خودش وصل نبود) —
        // خودکار برای وصل‌شدن دوباره تلاش کن.
        if (wasConnected &&
            (s == BtConnState.disconnected || s == BtConnState.error)) {
          _scheduleAutoReconnect();
        }
      });
      _initBluetooth();
    }
  }

  // ── اتصال خودکار بلوتوث ──────────────────────────────────────────────
  // رفع باگ «اتصال خودکار»: قبلاً فقط وقتی دقیقاً یک دستگاه Pair‌شده وجود
  // داشت خودکار وصل می‌شد، و هیچ تلاش مجددی بعد از برگشتن اپ از پس‌زمینه
  // انجام نمی‌شد (کاربر مجبور بود اپ را کامل ببندد و باز کند). حالا:
  //  ۱) آدرس آخرین دستگاهِ متصل‌شده ذخیره و همیشه ابتدا امتحان می‌شود.
  //  ۲) در نبود آن، اگر فقط یک دستگاه Pair شده باشد همان انتخاب می‌شود.
  //  ۳) در didChangeAppLifecycleState وقتی اپ به پیش‌زمینه برمی‌گردد و
  //     دیگر متصل نیست، همین منطق دوباره اجرا می‌شود — بدون لمس دستی.
  Future<void> _initBluetooth() async {
    final supported = await BtHidService.instance.initialize();
    if (!mounted) return;
    if (!supported) {
      _showErrorOnce(
        BtHidService.instance.lastInitError ??
            'این گوشی از حالت کنترل بلوتوثی پشتیبانی نمی‌کند',
      );
      return;
    }
    if (BtHidService.instance.isConnected) return;

    var devices = await BtHidService.instance.bondedDevices();
    if (devices.isEmpty && BtHidService.instance.lastCallWasPermissionDenied) {
      // رفع همان باگ «مجوز هنوز نرسیده» — یک تلاش خودکار مجدد بعد از کمی تاخیر
      await Future.delayed(const Duration(milliseconds: 400));
      devices = await BtHidService.instance.bondedDevices();
    }
    if (!mounted || devices.isEmpty) return;

    final lastAddress = await BtHidService.instance.lastDeviceAddress();
    BtBondedDevice? remembered;
    if (lastAddress != null) {
      for (final d in devices) {
        if (d.address == lastAddress) {
          remembered = d;
          break;
        }
      }
    }

    if (remembered != null) {
      await BtHidService.instance.connect(remembered.address);
    } else if (devices.length == 1) {
      await BtHidService.instance.connect(devices.first.address);
    }
  }

  void _scheduleAutoReconnect() {
    _retryTimer?.cancel();
    if (_reconnectAttempts >= _maxAutoRetries) return;
    _reconnectAttempts++;
    final delaySeconds = _reconnectAttempts.clamp(1, 4); // 1,2,3,4,4 ثانیه
    _retryTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!mounted || BtHidService.instance.isConnected) return;
      if (_reconnectAttempts >= 3) {
        // چند تلاش ساده شکست خورده — ثبت HID را کامل ریست کن (رفع باگ
        // «تا ری‌استارت اپ وصل نمی‌شود») و سپس دوباره تلاش برای اتصال.
        await BtHidService.instance.hardReset();
        if (!mounted) return;
      }
      await _initBluetooth();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // رفع باگ «باید کامل اپ را ری‌استارت کنم»: هر بار که اپ از پس‌زمینه
    // برمی‌گردد، اگر هنوز به بلوتوث تلویزیون وصل نیستیم، دوباره تلاش
    // برای ثبت و اتصال خودکار انجام می‌شود.
    if (state == AppLifecycleState.resumed &&
        widget.mode.isBluetooth &&
        !BtHidService.instance.isConnected) {
      _initBluetooth();
    }
  }

  Future<void> _pickDevice() async {
    var devices = await BtHidService.instance.bondedDevices();

    // ⚠️ رفع باگ: قبلاً وقتی مجوز BLUETOOTH_CONNECT هنوز واقعاً به سیستم
    // نرسیده بود (مثلاً چند صد میلی‌ثانیه تاخیر بعد از تایید کاربر —
    // روی برخی گوشی‌ها مثل شیائومی/ردمی دیده شده)، سمت اندروید
    // SecurityException می‌گرفت و لیست خالی برمی‌گشت، و پیام گمراه‌کننده‌ی
    // «دستگاهی یافت نشد» نشان داده می‌شد درحالی‌که تلویزیون واقعاً
    // Pair بود. حالا این حالت را جدا تشخیص می‌دهیم و یک بار خودکار
    // دوباره تلاش می‌کنیم.
    if (devices.isEmpty && BtHidService.instance.lastCallWasPermissionDenied) {
      await PermissionsService.requestBluetoothPermissions();
      await Future.delayed(const Duration(milliseconds: 400));
      devices = await BtHidService.instance.bondedDevices();
    }
    if (!mounted) return;

    if (devices.isEmpty) {
      final permissionIssue = BtHidService.instance.lastCallWasPermissionDenied;
      _showErrorOnce(
        permissionIssue
            ? 'مجوز بلوتوث هنوز فعال نشده — از تنظیمات گوشی ← اپ‌ها ← کنترل هوشمند دوو ← مجوزها، دسترسی «دستگاه‌های اطراف» را فعال کنید'
            : 'هیچ دستگاهی پیدا نشد — اول باید بلوتوث تلویزیون را از «تنظیمات گوشی ← بلوتوث» Pair کنید',
      );
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
    if (widget.mode.isBluetooth) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _retryTimer?.cancel();
    _btSub?.cancel();
    super.dispose();
  }

  /// نمایش هر پیام خطای مشخص فقط یک‌بار (به‌صورت دیالوگ با دکمه‌ی «باشه»)
  /// به‌جای اسپم SnackBar در هر فشار دکمه. رفع باگ «خطاها هی تکرار می‌شوند».
  void _showErrorOnce(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final sameRecentError = _lastErrorShown == message &&
        _lastErrorAt != null &&
        now.difference(_lastErrorAt!) < const Duration(seconds: 5);
    if (_errorDialogOpen || sameRecentError) return;

    _lastErrorShown = message;
    _lastErrorAt = now;
    _errorDialogOpen = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          side: const BorderSide(color: AppColors.line),
        ),
        title: const Text('خطا',
            style: TextStyle(color: AppColors.text1, fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(color: AppColors.text2, height: 1.8)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('باشه',
                style: TextStyle(color: AppColors.btAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((_) => _errorDialogOpen = false);
  }

  /// روش جایگزین اتصال: گوشی را قابل‌مشاهده می‌کند و راهنمای وصل‌شدن از
  /// روی خودِ تلویزیون را نشان می‌دهد. برای تلویزیون‌هایی لازم است که
  /// اتصال HID آغازشده از سمت گوشی را نمی‌پذیرند (نوسان در-حال-اتصال ⇄
  /// قطع‌شده) — طبق تجربه‌ی مستندشده‌ی توسعه‌دهندگان دیگر با همین API
  /// اندروید (BluetoothHidDevice)، برخی میزبان‌ها فقط وقتی خودشان
  /// اتصال را آغاز کنند آن را می‌پذیرند.
  Future<void> _tryAlternativeConnection() async {
    final permitted =
        await PermissionsService.requestDiscoverabilityPermission();
    if (!permitted) {
      _showErrorOnce('برای قابل‌مشاهده کردن گوشی، مجوز بلوتوث لازم است');
      return;
    }
    final ok = await BtHidService.instance.requestDiscoverable();
    if (!mounted) return;
    if (!ok) {
      _showErrorOnce('باز کردن حالت قابل‌مشاهده ناموفق بود');
      return;
    }
    final name = await BtHidService.instance.localDeviceName();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          side: const BorderSide(color: AppColors.line),
        ),
        title: const Text('اتصال از روی تلویزیون',
            style: TextStyle(color: AppColors.text1, fontWeight: FontWeight.w700)),
        content: Text(
          'گوشی شما تا ۲ دقیقه قابل‌مشاهده است.\n\n'
          'حالا از روی خودِ تلویزیون:\n'
          '۱. تنظیمات ← بلوتوث ← افزودن دستگاه\n'
          '۲. نام «${name ?? 'کنترل هوشمند دوو'}» را از لیست انتخاب کنید\n\n'
          'این روش وقتی اتصال از داخل اپ مدام قطع می‌شود، معمولاً '
          'قابل‌اعتمادتر است.',
          style: const TextStyle(color: AppColors.text2, height: 1.8),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('متوجه شدم',
                style: TextStyle(color: AppColors.btAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
      _showErrorOnce(result.message!);
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
          child: Column(
            children: [
              if (_showAlternativeHint) _AlternativeConnectionBanner(
                onTap: _tryAlternativeConnection,
              ),
              Expanded(
                child: widget.size == RemoteSize.large
                    ? _LargeRemote(accent: accent, onPress: _press)
                    : _SmallRemote(
                        accent: accent, mode: widget.mode, onPress: _press),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── بنر پیشنهاد روش جایگزین اتصال (وقتی اتصال از داخل اپ نوسان دارد) ──
class _AlternativeConnectionBanner extends StatelessWidget {
  const _AlternativeConnectionBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.btAccentDim,
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
            border: Border.all(color: AppColors.btAccent.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.btAccentLight, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'اتصال از اپ ناموفق است — روش جایگزین را امتحان کنید (اتصال از روی تلویزیون)',
                  style: TextStyle(color: AppColors.text1, fontSize: 12),
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: AppColors.btAccentLight),
            ],
          ),
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

        // ── شبکه‌ی ۳×۳ صدا/خانه/کانال — دقیقاً طبق طرح HTML مرجع ──────────
        // ردیف ۱: + / Home / ▲Ch
        Row(
          children: [
            Expanded(
              child: RemoteButton(
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
                onTap: () => onPress('ch_up'),
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ردیف ۲: برچسب VOL / Mute / برچسب CH
        Row(
          children: [
            Expanded(
              child: Center(
                child: Text('VOL', style: TextStyle(fontSize: 11, color: AppColors.text3, fontWeight: FontWeight.w700)),
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
              child: Center(
                child: Text('CH', style: TextStyle(fontSize: 11, color: AppColors.text3, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ردیف ۳: − / Menu / ▼Ch
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
                onTap: () => onPress('menu'),
                child: const Icon(Icons.menu_rounded),
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

        // ── دکمه‌های رنگی (هم IR و هم بلوتوث — کدهای واقعی هسته لینوکس) ──
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

        // ── ردیف: Previous / Stop / Next ─────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('prev'),
                child: const Icon(Icons.skip_previous_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('stop'),
                child: const Icon(Icons.stop_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                onTap: () => onPress('next'),
                child: const Icon(Icons.skip_next_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── ردیف: Exit / Record / EPG ────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'EXIT',
                onTap: () => onPress('exit'),
                child: const Icon(Icons.logout_rounded, size: 16),
              ),
            ),
            const SizedBox(width: 8),
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
        const SizedBox(height: 8),

        // ── ردیف: Text / Audio / Subtitle ────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'TEXT',
                onTap: () => onPress('text'),
                child: const Icon(Icons.article_outlined, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'AUDIO',
                onTap: () => onPress('audio_track'),
                child: const Icon(Icons.audiotrack_rounded, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'SUB.T',
                onTap: () => onPress('subtitle'),
                child: const Icon(Icons.subtitles_outlined, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── ردیف: Radio / Zoom / Shift ───────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'RADIO',
                onTap: () => onPress('radio'),
                child: const Icon(Icons.radio_rounded, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'ZOOM',
                onTap: () => onPress('zoom'),
                child: const Icon(Icons.zoom_in_rounded, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RemoteButton(
                shape: RemoteButtonShape.tiny,
                label: 'SHIFT',
                onTap: () => onPress('shift'),
                child: const Icon(Icons.keyboard_capslock_rounded, size: 16),
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
class _SmallRemote extends StatefulWidget {
  const _SmallRemote(
      {required this.accent, required this.mode, required this.onPress});
  final Color accent;
  final RemoteMode mode;
  final void Function(String) onPress;

  @override
  State<_SmallRemote> createState() => _SmallRemoteState();
}

class _SmallRemoteState extends State<_SmallRemote> {
  // ⚠️ رفع باگ «دکمه موس کار نمی‌کند اصلاً»: قبلاً این دکمه مستقیم یک
  // کلیک موس ارسال می‌کرد (بدون ارتباط با تاچ‌پد پایین)، درحالی‌که طبق
  // طرح رابط کاربری این دکمه باید حالت «فعال/غیرفعال» موس را کنترل کند.
  // حالا این وضعیت اینجا نگه داشته می‌شود و به تاچ‌پد پاس داده می‌شود.
  bool _mouseActive = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final mode = widget.mode;
    final onPress = widget.onPress;
    final locked = !mode.supportsTouchpad;
    return ListView(
      children: [
        // ── Power / Mic ──────────────────────────────────────────────────
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
                disabled: locked,
                accent: accent.withOpacity(0.2),
                onTap: () => onPress('mic'),
                child: const Icon(Icons.mic_none_rounded),
              ),
            ),
          ],
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

        // ── Vol+ / Mouse (فقط بلوتوث) / CH+ ─────────────────────────────
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
                disabled: locked,
                accent: _mouseActive
                    ? accent.withOpacity(0.55)
                    : accent.withOpacity(0.15),
                onTap: () => setState(() => _mouseActive = !_mouseActive),
                child: const Icon(Icons.mouse_rounded),
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
        Touchpad(active: _mouseActive, locked: locked),
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
