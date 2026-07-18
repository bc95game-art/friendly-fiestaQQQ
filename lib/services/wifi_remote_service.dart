import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق وای‌فای
///
///  پروتکل EShare — از روی کد Java واقعی دیکامپایل‌شده (jadx)
///
///  ── کشف تلویزیون (FindDeviceActivity.java) ──────────────────────────
///  EShare از UDP broadcast برای یافتن تلویزیون استفاده می‌کند:
///    ۱. یک بسته ۵۰ بایتی با payload «FindECloudBox» به پورت 48689 broadcast می‌فرستد
///    ۲. تلویزیون (EShare Server) جواب UDP می‌دهد
///    ۳. IP تلویزیون از آدرس فرستنده جواب استخراج می‌شود
///
///  فرمت بسته UDP (از FindDeviceActivity.R()):
///    bytes  0-11: 0x00 (سه int32 = صفر)
///    bytes 12-15: طول «FindECloudBox» به صورت big-endian int32 = 13
///    bytes 16-19: 0x00
///    bytes 20-32: «FindECloudBox» (13 بایت ASCII)
///    bytes 33-49: 0x00 (padding)
///
///  آدرس broadcast (از FindDeviceActivity.F()):
///    - روی WiFi: subnet broadcast مثل 192.168.1.255
///    - روی hotspot اندروید: 192.168.43.255
///    - fallback: 255.255.255.255
///
///  ── پروتکل TCP بعد از اتصال ─────────────────────────────────────────
///  پورت: 2012  (از intent.getIntExtra("devicePort", 2012))
///  فرمت: COMMAND\r\nparam\r\n\r\n
///  HeartBeat: هر 3000ms — «HeartBeat\r\nlive\r\n\r\n»
/// ══════════════════════════════════════════════════════════════════════
class WifiRemoteService {
  WifiRemoteService._();
  static final WifiRemoteService instance = WifiRemoteService._();

  static const int defaultPort = 2012;
  static const int _udpDiscoveryPort = 48689;
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

  // throttle ماوس — از f3194b=55 در c.java
  int _lastMouseMs = 0;
  static const _mouseThrottleMs = 55;

  void _emit(WifiConnState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  کشف UDP — دقیقاً مثل FindDeviceActivity.R() و F()
  // ══════════════════════════════════════════════════════════════════════

  /// بسته UDP برای کشف تلویزیون
  /// از FindDeviceActivity.R() در EShare:
  ///   bytes 12-15 = طول payload (int32 big-endian)
  ///   bytes 20..  = «FindECloudBox»
  static List<int> _buildDiscoveryPacket() {
    final payload = List<int>.filled(50, 0);
    final text = 'FindECloudBox'.codeUnits; // 13 بایت
    // bytes 12-15: طول (big-endian) — 0x0000000D
    payload[12] = 0;
    payload[13] = 0;
    payload[14] = 0;
    payload[15] = text.length; // 13
    // bytes 20-32: «FindECloudBox»
    for (int i = 0; i < text.length; i++) {
      payload[20 + i] = text[i];
    }
    return payload;
  }

  /// آدرس‌های broadcast برای ارسال UDP
  /// از FindDeviceActivity.F() در EShare
  Future<List<String>> _broadcastAddresses() async {
    final addrs = <String>{};

    // ۱. subnet broadcast شبکه‌های فعال (WiFi یا hotspot)
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
          if (parts.length == 4) {
            addrs.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {}

    // ۲. آدرس‌های ثابت hotspot اندروید (از EShare fallback)
    addrs.add('192.168.43.255'); // hotspot اندروید
    addrs.add('192.168.49.255'); // WiFi sharing اندروید
    addrs.add('192.168.1.255'); // روتر خانگی رایج
    addrs.add('192.168.0.255'); // روتر خانگی رایج ۲
    addrs.add('255.255.255.255'); // broadcast عمومی (EShare fallback)

    return addrs.toList();
  }

  /// اتصال خودکار — UDP broadcast مثل EShare
  Future<bool> autoConnect() async {
    if (_state == WifiConnState.connecting) return false;
    lastError = null;
    _emit(WifiConnState.connecting);

    final ip = await _udpDiscover();

    if (ip != null) {
      return _openSocket(ip, defaultPort);
    }

    lastError = 'تلویزیون پیدا نشد\n'
        '• hotspot گوشی را روشن کنید و تلویزیون را به آن وصل کنید\n'
        '• یا هر دو دستگاه را به یک WiFi وصل کنید\n'
        '• اگر IP تلویزیون را می‌دانید، دستی وارد کنید';
    _emit(WifiConnState.error);
    return false;
  }

  /// جستجوی UDP — ارسال «FindECloudBox» به همه broadcast و دریافت جواب
  Future<String?> _udpDiscover() async {
    final packet = _buildDiscoveryPacket();
    final broadcasts = await _broadcastAddresses();

    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;

      // ارسال به همه آدرس‌های broadcast
      for (final bcast in broadcasts) {
        try {
          sock.send(packet, InternetAddress(bcast), _udpDiscoveryPort);
        } catch (_) {}
      }

      // انتظار برای جواب تلویزیون — تا ۵ ثانیه
      final completer = Completer<String?>();
      final timer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      sock.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = sock?.receive();
          if (dg != null && !completer.isCompleted) {
            timer.cancel();
            // IP تلویزیون = آدرس فرستنده جواب UDP
            completer.complete(dg.address.address);
          }
        }
      });

      final ip = await completer.future;
      sock.close();
      return ip;
    } catch (e) {
      sock?.close();
      return null;
    }
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
      // ۱. auth — از HeartBeatServer.java خط 110
      await _rawSetup('auth\r\n/storage/emulated/0 $port Onelong\r\n\r\n');
      // ۲. getFeatures — از HeartBeatServer.java خط 124-128
      await _rawSetup('getFeatures\r\nDaewooRemote\r\n\r\n');
      // ۳. فعال کردن cursor ماوس
      await _rawSetup('MOUSEENABLEEVENT\r\n1\r\n\r\n');

      // اگر socket در حین setup از بین رفت
      if (_socket == null) {
        lastError = 'تلویزیون اتصال را بلافاصله قطع کرد';
        _emit(WifiConnState.error);
        return false;
      }

      _emit(WifiConnState.connected);
      _startHeartbeat();

      _socket!.listen(
        (_) {},
        onError: (_) { _cleanup(); _emit(WifiConnState.disconnected); },
        onDone: () { _cleanup(); _emit(WifiConnState.disconnected); },
        cancelOnError: true,
      );
      return true;
    } on SocketException catch (e) {
      lastError = switch (e.osError?.errorCode) {
        111 => 'پورت $port بسته است — آیا EShare Server روی تلویزیون نصب است؟',
        113 => 'IP $ip در شبکه پیدا نشد',
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

  /// HeartBeat هر ۳ ثانیه — از HeartBeatServer.java
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _raw('HeartBeat\r\nlive\r\n\r\n'),
    );
  }

  Future<void> disconnect({bool silent = false}) async {
    if (_socket != null) {
      try { await _rawSetup('MOUSEENABLEEVENT\r\n0\r\n\r\n'); } catch (_) {}
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    _connectedIp = null;
    _connectedPort = null;
    if (!silent) _emit(WifiConnState.disconnected);
  }

  // ── _rawSetup: ارسال در مرحله setup — بدون emit state ──────────────────
  Future<void> _rawSetup(String msg) async {
    final s = _socket;
    if (s == null) return;
    try { s.add(msg.codeUnits); await s.flush(); }
    catch (_) { _cleanup(); }
  }

  // ── _raw: ارسال در حین کار عادی — با emit disconnect در صورت خطا ────────
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
  //  دستورات — پروتکل EShare دقیق
  // ══════════════════════════════════════════════════════════════════════

  Future<bool> sendKey(String key) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final code = _keyCode(key);
    if (code == null) return Future.value(false);
    return _raw('KEYEVENT\r\n$code\r\n\r\n');
  }

  Future<bool> sendMouseMove(int dx, int dy) {
    if (_state != WifiConnState.connected) return Future.value(false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < _mouseThrottleMs) return Future.value(true);
    _lastMouseMs = now;
    return _raw('AIRMOUSEEVNET\r\n${dx.toDouble()}\r\n${dy.toDouble()}\r\n2\r\n\r\n');
  }

  Future<bool> sendMouseClick() async {
    if (_state != WifiConnState.connected) return false;
    await _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n0\r\n\r\n');
    await Future.delayed(const Duration(milliseconds: 50));
    return _raw('AIRMOUSEEVNET\r\n0.0\r\n0.0\r\n1\r\n\r\n');
  }

  Future<bool> sendVolume(int vol) {
    if (_state != WifiConnState.connected) return Future.value(false);
    return _raw('MediaControl\r\nsetVolume ${vol.clamp(0, 30)}\r\n\r\n');
  }

  static int? _keyCode(String key) => const {
    'back'       : 4,
    'home'       : 3,
    'menu'       : 82,
    'up'         : 19,
    'down'       : 20,
    'left'       : 21,
    'right'      : 22,
    'ok'         : 23,
    'vol_up'     : 24,
    'vol_down'   : 25,
    'mute'       : 164,
    'power'      : 26,
    'source'     : 178,
    'play_pause' : 85,
    'rewind'     : 89,
    'forward'    : 90,
    'ch_up'      : 166,
    'ch_down'    : 167,
    'stop'       : 86,
    'next'       : 87,
    'prev'       : 88,
  }[key];
}
