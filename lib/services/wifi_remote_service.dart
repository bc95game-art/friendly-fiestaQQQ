import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق وای‌فای
///
///  پروتکل EShare — از روی کد Java واقعی دیکامپایل‌شده (jadx):
///
///  فرمت پیام:   COMMAND\r\nparam\r\n\r\n
///  پورت:        2012  (از intent.getIntExtra("devicePort", 2012))
///  HeartBeat:   هر 3000ms — "HeartBeat\r\nlive\r\n\r\n"
///               (از HeartBeatServer.java خط 82: sendEmptyMessageDelayed(0,3000))
///  Auth:        "auth\r\n{sdPath} {port} Onelong\r\n\r\n"
///               (از HeartBeatServer.java خط 110)
///  getFeatures: "getFeatures\r\n{model}\r\n\r\n"
///               (از HeartBeatServer.java خط 124-128)
///  KEYEVENT:    "KEYEVENT\r\n{androidKeyCode}\r\n\r\n"
///               (از tvremote/c.java متد p())
///  Air Mouse:   "AIRMOUSEEVNET\r\n{x}\r\n{y}\r\n{action}\r\n\r\n"
///               توجه: EVNET نه EVENT — تایپو در کد اصلی EShare است
///               (از tvremote/c.java متد a())
///               action=0: press  action=1: release  action=2: move
///  throttle:    55ms برای action=2 (از f3194b=55 در c.java)
///  Mouse enable:"MOUSEENABLEEVENT\r\n1\r\n\r\n"
///               وقتی AirMouseActivity شروع می‌شود (از tvremote/c.java متد q())
///  Volume:      "MediaControl\r\nsetVolume {vol}\r\n\r\n"
///               بازه 0-30 (از tvremote/c.java متد A())
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteService {
  WifiRemoteService._();
  static final WifiRemoteService instance = WifiRemoteService._();

  /// پورت پیش‌فرض EShare — تأیید از کد Java:
  /// intent.getIntExtra("devicePort", 2012)
  static const int defaultPort = 2012;

  /// timeout اتصال — از HeartBeatServer.java خط 57:
  /// socket.connect(new InetSocketAddress(...), 3000)
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

  /// throttle حرکت ماوس — از f3194b=55 در tvremote/c.java
  int _lastMouseMs = 0;
  static const _mouseThrottleMs = 55;

  /// جلوگیری از ارسال event تکراری به stream
  void _emit(WifiConnState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
  }

  // ── شناسایی IP‌های احتمالی TV در شبکه ──────────────────────────────────
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

          // اسکن زیرشبکه — آدرس‌های رایج‌تر TV اول
          for (final i in [1, 2, 100, 101, 102, 103, 104, 105, 200, 201]) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
          for (int i = 3; i <= 20; i++) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
          for (int i = 106; i <= 120; i++) {
            if (i != myOctet) candidates.add('$subnet.$i');
          }
        }
      }
    } catch (_) {}

    // fallback: hotspot اندروید
    if (candidates.isEmpty) {
      for (int i = 1; i <= 20; i++) candidates.add('192.168.43.$i');
      for (int i = 100; i <= 110; i++) candidates.add('192.168.43.$i');
      for (int i = 1; i <= 10; i++) candidates.add('192.168.49.$i');
    }

    return candidates.toList();
  }

  // ── اتصال خودکار ──────────────────────────────────────────────────────
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
      Socket.connect(ip, defaultPort,
              timeout: const Duration(milliseconds: 700))
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
          '• گوشی و تلویزیون باید روی یک شبکه WiFi باشند\n'
          '• یا IP تلویزیون را دستی وارد کنید';
      _emit(WifiConnState.error);
      return false;
    }

    return _openSocket(ip, defaultPort);
  }

  // ── اتصال دستی ────────────────────────────────────────────────────────
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
      //
      // ۱. Auth — از HeartBeatServer.java خط 110:
      //    f2.getOutputStream().write(("auth\r\n" + sdcardPath + " " + port + " " + "Onelong" + "\r\n\r\n").getBytes())
      await _rawSetup('auth\r\n/storage/emulated/0 $port Onelong\r\n\r\n');

      // ۲. getFeatures — از HeartBeatServer.java خط 124-128:
      //    EShare پاسخ می‌خواند، ما آن را نادیده می‌گیریم (در listener)
      await _rawSetup('getFeatures\r\nDaewooRemote\r\n\r\n');

      // ۳. فعال کردن cursor ماوس روی TV
      //    از AirMouseActivity: وقتی Activity شروع می‌شود w.q(1) صدا می‌زند
      //    q(1) → MOUSEENABLEEVENT\r\n1\r\n\r\n
      await _rawSetup('MOUSEENABLEEVENT\r\n1\r\n\r\n');

      // ── رفع باگ: اگر socket در حین setup از بین رفت، وصل نشو ──────────
      // _rawSetup در صورت خطا _socket را null می‌کند ولی state emit نمی‌کند
      // اینجا بررسی می‌کنیم تا از emit اشتباه state=connected جلوگیری کنیم
      if (_socket == null) {
        lastError = 'تلویزیون اتصال را بلافاصله قطع کرد';
        _emit(WifiConnState.error);
        return false;
      }

      _emit(WifiConnState.connected);

      // ── شروع HeartBeat هر ۳ ثانیه — از HeartBeatServer.java خط 82 ──
      _startHeartbeat();

      // ── listener برای تشخیص قطع اتصال ──────────────────────────────
      _socket!.listen(
        (_) {}, // پاسخ‌های TV (مثل server_features:...) نادیده گرفته می‌شوند
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
        113 => 'IP $ip پیدا نشد — شبکه را بررسی کنید',
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

  /// HeartBeat — از HeartBeatServer.java:
  ///   sendEmptyMessageDelayed(0, 3000)  →  هر ۳۰۰۰ms
  ///   l(socket): socket.getOutputStream().write("HeartBeat\r\nlive\r\n\r\n".getBytes())
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _raw('HeartBeat\r\nlive\r\n\r\n'),
    );
  }

  Future<void> disconnect({bool silent = false}) async {
    // اطلاع به TV که cursor ماوس خاموش شود
    if (_socket != null) {
      try {
        await _rawSetup('MOUSEENABLEEVENT\r\n0\r\n\r\n');
      } catch (_) {}
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _connectedIp = null;
    _connectedPort = null;
    if (!silent) {
      _emit(WifiConnState.disconnected);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  دو متد ارسال جداگانه — برای رفع باگ state machine
  // ══════════════════════════════════════════════════════════════════════

  /// _rawSetup — برای مرحله setup (قبل از emit(connected))
  /// در صورت خطا: فقط cleanup می‌کند، state تغییر نمی‌دهد
  /// چرا جدا؟ چون _raw در صورت خطا emit(disconnected) می‌کند، ولی در setup
  /// هنوز emit(connected) نشده و state غلط می‌شود
  Future<void> _rawSetup(String msg) async {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(msg.codeUnits);
      await s.flush();
    } catch (_) {
      _cleanup(); // socket از بین رفت — caller چک می‌کند _socket == null
    }
  }

  /// _raw — برای ارسال در حین کار عادی (بعد از emit(connected))
  /// در صورت خطا: cleanup + emit(disconnected) تا UI به صفحه اتصال برگردد
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

  // ══════════════════════════════════════════════════════════════════════
  //  دستورات عمومی — پروتکل EShare دقیق
  // ══════════════════════════════════════════════════════════════════════

  /// کلید — از tvremote/c.java متد p():
  /// f2.getOutputStream().write(("KEYEVENT\r\n" + i2 + "\r\n\r\n").getBytes())
  Future<bool> sendKey(String key) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final code = _keyCode(key);
    if (code == null) return Future.value(false);
    return _raw('KEYEVENT\r\n$code\r\n\r\n');
  }

  /// حرکت ماوس — از tvremote/c.java متد a():
  /// ("AIRMOUSEEVNET\r\n" + f2 + "\r\n" + f3 + "\r\n" + i2 + "\r\n\r\n")
  /// توجه: EVNET نه EVENT — این تایپو در کد اصلی EShare است، TV همین را expect دارد
  /// action=2: move — throttle 55ms (f3194b=55)
  Future<bool> sendMouseMove(int dx, int dy) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < _mouseThrottleMs) return Future.value(true);
    _lastMouseMs = now;
    // Java: float f2 → toString() مثلاً "10.0" — Dart: toDouble() همین را می‌دهد
    return _raw(
        'AIRMOUSEEVNET\r\n${dx.toDouble()}\r\n${dy.toDouble()}\r\n2\r\n\r\n');
  }

  /// کلیک — از AirMouseActivity: برای tap روی touchpad
  /// action=0 (press): AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n0\r\n\r\n
  /// action=1 (release): AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n1\r\n\r\n
  /// x=0, y=0 یعنی cursor در همان جای فعلی کلیک می‌شود (delta نسبی است)
  Future<bool> sendMouseClick() async {
    if (_state != WifiConnState.connected) return false;
    await _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n0\r\n\r\n');
    await Future.delayed(const Duration(milliseconds: 50));
    return _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n1\r\n\r\n');
  }

  /// صدا — از tvremote/c.java متد A():
  /// i("MediaControl\r\nsetVolume " + i2 + "\r\n\r\n")
  /// بازه 0-30 (از SeekBar در NewRemoteMainActivity)
  Future<bool> sendVolume(int vol) {
    if (_state != WifiConnState.connected) return Future.value(false);
    return _raw('MediaControl\r\nsetVolume ${vol.clamp(0, 30)}\r\n\r\n');
  }

  // ── نگاشت نام دکمه → کد کلید Android ──────────────────────────────────
  /// کدها از android.view.KeyEvent.KEYCODE_* — همین کدها که EShare در
  /// KEYEVENT می‌فرستد و Android TV آن‌ها را به‌عنوان KeyEvent.KEYCODE_*
  /// دریافت و پردازش می‌کند
  static int? _keyCode(String key) => const {
        'back': 4, // KEYCODE_BACK
        'home': 3, // KEYCODE_HOME
        'menu': 82, // KEYCODE_MENU
        'up': 19, // KEYCODE_DPAD_UP
        'down': 20, // KEYCODE_DPAD_DOWN
        'left': 21, // KEYCODE_DPAD_LEFT
        'right': 22, // KEYCODE_DPAD_RIGHT
        'ok': 23, // KEYCODE_DPAD_CENTER
        'vol_up': 24, // KEYCODE_VOLUME_UP
        'vol_down': 25, // KEYCODE_VOLUME_DOWN
        'mute': 164, // KEYCODE_VOLUME_MUTE
        'power': 26, // KEYCODE_POWER
        'source': 178, // KEYCODE_TV_INPUT
        'play_pause': 85, // KEYCODE_MEDIA_PLAY_PAUSE
        'rewind': 89, // KEYCODE_MEDIA_REWIND
        'forward': 90, // KEYCODE_MEDIA_FAST_FORWARD
        'ch_up': 166, // KEYCODE_CHANNEL_UP
        'ch_down': 167, // KEYCODE_CHANNEL_DOWN
        'stop': 86, // KEYCODE_MEDIA_STOP
        'next': 87, // KEYCODE_MEDIA_NEXT
        'prev': 88, // KEYCODE_MEDIA_PREVIOUS
      }[key];
}
