import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق وای‌فای
///
///  پروتکل دقیق EShare (از روی کد واقعی دیکامپایل‌شده):
///
///  اتصال: TCP به پورت 2012 (پورت پیش‌فرض EShare)
///
///  فرمت هر پیام:
///    COMMAND_NAME\r\n
///    param1\r\n
///    param2\r\n
///    \r\n           ← خط خالی = پایان پیام
///
///  دستورات:
///    HeartBeat\r\nlive\r\n\r\n                        ← هر ۳ ثانیه
///    auth\r\n{path} {port} Onelong\r\n\r\n            ← بعد از اتصال
///    getFeatures\r\n{model}\r\n\r\n                   ← بعد از auth
///    MOUSEENABLEEVENT\r\n1\r\n\r\n                    ← فعال کردن ماوس
///    KEYEVENT\r\n{androidKeyCode}\r\n\r\n             ← کلید
///    AIRMOUSEEVNET\r\n{dx}\r\n{dy}\r\n{action}\r\n\r\n ← ماوس
///    MediaControl\r\nsetVolume {vol}\r\n\r\n          ← صدا (0-30)
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteService {
  WifiRemoteService._();
  static final WifiRemoteService instance = WifiRemoteService._();

  /// پورت پیش‌فرض EShare — از کد Java واقعی:
  /// intent.getIntExtra("devicePort", 2012)
  static const int defaultPort = 2012;

  /// timeout اتصال — مثل EShare: 3000ms
  static const _connectTimeout = Duration(seconds: 3);

  final _stateCtrl = StreamController<WifiConnState>.broadcast();
  Stream<WifiConnState> get stateStream => _stateCtrl.stream;

  WifiConnState _state = WifiConnState.disconnected;
  WifiConnState get state => _state;
  bool get isConnected => _state == WifiConnState.connected;

  Socket? _socket;
  String? _connectedIp;
  int? _connectedPort;
  Timer? _heartbeatTimer;
  String? get connectedIp => _connectedIp;
  int? get connectedPort => _connectedPort;
  String? lastError;

  /// throttle حرکت ماوس — مثل EShare: 55ms
  int _lastMouseMs = 0;
  static const _mouseThrottleMs = 55;

  void _emit(WifiConnState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  // ── شناسایی IP‌های احتمالی TV در شبکه ──────────────────────────────────
  /// گوشی و تلویزیون باید روی یک شبکه WiFi باشند (یا TV به hotspot گوشی وصل باشد).
  /// این تابع تمام آدرس‌های احتمالی زیرشبکه‌های فعال را برمی‌گرداند.
  Future<List<String>> detectTvIps() async {
    final candidates = <String>{};

    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
          final myOctet = int.tryParse(parts[3]) ?? 0;

          // اسکن کل زیرشبکه — ابتدا آدرس‌های رایج‌تر برای TV
          // آدرس‌های رایج Android TV/Smart TV در شبکه خانگی:
          for (final i in [1, 2, 100, 101, 102, 103, 104, 105, 200, 201]) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
          // بقیه محدوده
          for (int i = 3; i <= 20; i++) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
          for (int i = 106; i <= 120; i++) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
        }
      }
    } catch (_) {}

    if (candidates.isEmpty) {
      // زیرشبکه‌های پیش‌فرض hotspot اندروید
      for (int i = 1; i <= 20; i++) candidates.add('192.168.43.$i');
      for (int i = 100; i <= 110; i++) candidates.add('192.168.43.$i');
      for (int i = 1; i <= 10; i++) candidates.add('192.168.49.$i');
    }

    return candidates.toList();
  }

  // ── اتصال خودکار — اسکن شبکه برای پورت 2012 ──────────────────────────
  Future<bool> autoConnect() async {
    if (_state == WifiConnState.connecting) return false;
    lastError = null;
    _emit(WifiConnState.connecting);

    final ips = await detectTvIps();
    if (ips.isEmpty) {
      lastError = 'هیچ شبکه‌ای پیدا نشد';
      _emit(WifiConnState.error);
      return false;
    }

    final completer = Completer<String?>();
    var pending = ips.length;

    for (final ip in ips) {
      Socket.connect(ip, defaultPort, timeout: const Duration(milliseconds: 700))
          .then((s) {
        s.destroy();
        if (!completer.isCompleted) completer.complete(ip);
      }).catchError((_) {
        pending--;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }

    final ip = await completer.future
        .timeout(const Duration(seconds: 10), onTimeout: () => null);

    if (ip == null) {
      lastError = 'تلویزیون پیدا نشد\n'
          '• مطمئن شوید گوشی و تلویزیون به یک شبکه WiFi وصل هستند\n'
          '• یا IP تلویزیون را دستی وارد کنید';
      _emit(WifiConnState.error);
      return false;
    }

    return _openSocket(ip, defaultPort);
  }

  // ── اتصال دستی به IP و پورت ────────────────────────────────────────────
  Future<bool> connect(String ip, {int port = defaultPort}) async {
    if (_state == WifiConnState.connecting) return false;
    await disconnect(silent: true);
    lastError = null;
    _emit(WifiConnState.connecting);
    return _openSocket(ip, port);
  }

  Future<bool> _openSocket(String ip, int port) async {
    try {
      await disconnect(silent: true);

      _socket = await Socket.connect(ip, port, timeout: _connectTimeout);
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _connectedIp = ip;
      _connectedPort = port;

      // ── دنباله راه‌اندازی — دقیقاً مثل EShare HeartBeatServer.java ──
      // ۱. auth
      await _raw('auth\r\n/storage/emulated/0 $port Onelong\r\n\r\n');
      // ۲. درخواست قابلیت‌های TV
      await _raw('getFeatures\r\nDaewooRemote\r\n\r\n');
      // ۳. فعال کردن حالت ماوس
      await _raw('MOUSEENABLEEVENT\r\n1\r\n\r\n');
      // ۴. سوئیچ به حالت touch (نه mirror)
      await _raw('SWICHEVENT\r\n0\r\n\r\n');

      _emit(WifiConnState.connected);

      // ── شروع HeartBeat هر ۳ ثانیه — دقیقاً مثل EShare ──
      _startHeartbeat();

      _socket!.listen(
        (_) {}, // پاسخ‌های TV نادیده گرفته می‌شوند (برای این نسخه)
        onError: (_) {
          _cleanup();
          _emit(WifiConnState.disconnected);
        },
        onDone: () {
          _cleanup();
          _emit(WifiConnState.disconnected);
        },
        cancelOnError: true,
      );
      return true;
    } on SocketException catch (e) {
      lastError = switch (e.osError?.errorCode) {
        111 => 'پورت $port بسته است — آیا EShare Server روی تلویزیون نصب است؟',
        113 => 'IP $ip در شبکه پیدا نشد — شبکه را بررسی کنید',
        _ => 'خطا در اتصال (کد: ${e.osError?.errorCode})',
      };
      _emit(WifiConnState.error);
      return false;
    } on TimeoutException {
      lastError = 'مهلت اتصال تمام شد — تلویزیون پاسخ نداد';
      _emit(WifiConnState.error);
      return false;
    } catch (e) {
      lastError = 'خطا: $e';
      _emit(WifiConnState.error);
      return false;
    }
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket = null;
    _connectedIp = null;
    _connectedPort = null;
  }

  /// HeartBeat — دقیقاً مثل EShare: هر ۳۰۰۰ms پیام «HeartBeat\r\nlive\r\n\r\n»
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _raw('HeartBeat\r\nlive\r\n\r\n'),
    );
  }

  Future<void> disconnect({bool silent = false}) async {
    if (_socket != null) {
      try { await _raw('MOUSEENABLEEVENT\r\n0\r\n\r\n'); } catch (_) {}
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    _connectedIp = null;
    _connectedPort = null;
    if (!silent && _state != WifiConnState.disconnected) {
      _emit(WifiConnState.disconnected);
    }
  }

  // ── ارسال مستقیم رشته به سوکت ───────────────────────────────────────
  Future<bool> _raw(String msg) async {
    final s = _socket;
    if (s == null) return false;
    try {
      s.add(msg.codeUnits);
      await s.flush();
      return true;
    } catch (_) {
      _cleanup();
      _emit(WifiConnState.disconnected);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  دستورات عمومی — پروتکل EShare دقیق
  // ═══════════════════════════════════════════════════════════════════

  /// ارسال کلید — KEYEVENT\r\n{androidKeyCode}\r\n\r\n
  /// کدهای Android از کد واقعی EShare استخراج شده‌اند
  Future<bool> sendKey(String key) {
    final code = _keyCode(key);
    if (code == null) return Future.value(false);
    if (_state != WifiConnState.connected) return Future.value(false);
    return _raw('KEYEVENT\r\n$code\r\n\r\n');
  }

  /// حرکت ماوس — AIRMOUSEEVNET\r\n{dx}\r\n{dy}\r\n2\r\n\r\n
  /// action=2 یعنی حرکت (MOVE)
  /// throttle: هر ۵۵ms یک‌بار — دقیقاً مثل EShare (f3194b = 55)
  Future<bool> sendMouseMove(int dx, int dy) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < _mouseThrottleMs) return Future.value(true);
    _lastMouseMs = now;
    // مقادیر dx,dy به‌صورت float ارسال می‌شوند (مثل EShare)
    return _raw('AIRMOUSEEVNET\r\n${dx.toDouble()}\r\n${dy.toDouble()}\r\n2\r\n\r\n');
  }

  /// کلیک ماوس — action=0 (press) سپس action=1 (release)
  Future<bool> sendMouseClick() async {
    if (_state != WifiConnState.connected) return false;
    await _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n0\r\n\r\n');
    await Future.delayed(const Duration(milliseconds: 50));
    return _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n1\r\n\r\n');
  }

  /// کنترل صدا — MediaControl\r\nsetVolume {vol}\r\n\r\n
  /// بازه: 0 تا 30 (مثل SeekBar اصلی EShare)
  Future<bool> sendVolume(int vol) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final v = vol.clamp(0, 30);
    return _raw('MediaControl\r\nsetVolume $v\r\n\r\n');
  }

  // ── نگاشت نام دکمه → کد کلید Android ──────────────────────────────────
  /// این کدها مستقیماً از کد Java دیکامپایل‌شده EShare استخراج شده‌اند.
  /// EShare همین کدها را در دستور KEYEVENT می‌فرستد و TV آن‌ها را
  /// مثل KeyEvent.KEYCODE_* اندروید پردازش می‌کند.
  static int? _keyCode(String key) => const {
    'back'       : 4,    // KEYCODE_BACK
    'home'       : 3,    // KEYCODE_HOME
    'menu'       : 82,   // KEYCODE_MENU
    'up'         : 19,   // KEYCODE_DPAD_UP
    'down'       : 20,   // KEYCODE_DPAD_DOWN
    'left'       : 21,   // KEYCODE_DPAD_LEFT
    'right'      : 22,   // KEYCODE_DPAD_RIGHT
    'ok'         : 23,   // KEYCODE_DPAD_CENTER
    'vol_up'     : 24,   // KEYCODE_VOLUME_UP
    'vol_down'   : 25,   // KEYCODE_VOLUME_DOWN
    'mute'       : 164,  // KEYCODE_VOLUME_MUTE
    'power'      : 26,   // KEYCODE_POWER
    'source'     : 178,  // KEYCODE_TV_INPUT
    'play_pause' : 85,   // KEYCODE_MEDIA_PLAY_PAUSE
    'rewind'     : 89,   // KEYCODE_MEDIA_REWIND
    'forward'    : 90,   // KEYCODE_MEDIA_FAST_FORWARD
    'ch_up'      : 166,  // KEYCODE_CHANNEL_UP
    'ch_down'    : 167,  // KEYCODE_CHANNEL_DOWN
    'stop'       : 86,   // KEYCODE_MEDIA_STOP
    'next'       : 87,   // KEYCODE_MEDIA_NEXT
    'prev'       : 88,   // KEYCODE_MEDIA_PREVIOUS
  }[key];
}
