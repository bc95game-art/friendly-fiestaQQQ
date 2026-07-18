import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای برای نمایش در UI
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق وای‌فای محلی
/// ══════════════════════════════════════════════════════════════════════
///
///  روش اتصال:
///    ۱. گوشی hotspot (نقطه اتصال) باز می‌کند
///    ۲. تلویزیون به hotspot گوشی وصل می‌شود و یک IP دریافت می‌کند
///    ۳. این سرویس IP تلویزیون را خودکار شناسایی می‌کند:
///       - ابتدا جدول ARP خوانده می‌شود (دقیق‌ترین روش)
///       - در صورت شکست، زیرشبکه اسکن می‌شود
///    ۴. گوشی به TCP server تلویزیون وصل می‌شود و دستورات ارسال می‌کند
///
///  پروتکل: TCP socket — دستورات خطی ساده:
///    KEY:power | KEY:up | KEY:down | KEY:left | KEY:right | KEY:ok
///    KEY:back  | KEY:home | KEY:menu | KEY:source
///    KEY:vol_up | KEY:vol_down | KEY:mute
///    KEY:ch_up  | KEY:ch_down
///    KEY:play_pause | KEY:rewind | KEY:forward
///    MOUSE:dx,dy    ← حرکت نشانگر (مقادیر نسبی)
///    CLICK          ← کلیک چپ
///    HEARTBEAT      ← نگه‌داری اتصال
class WifiRemoteService {
  WifiRemoteService._();
  static final WifiRemoteService instance = WifiRemoteService._();

  // پورت‌های احتمالی که تلویزیون روی آن‌ها گوش می‌دهد
  static const List<int> tryPorts = [9000, 5000, 8686, 8080, 1234, 4321, 9090];
  static const _connectTimeout = Duration(seconds: 4);

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

  void _emit(WifiConnState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  // ── خواندن جدول ARP لینوکس ─────────────────────────────────────────────
  /// /proc/net/arp دستگاه‌های متصل به hotspot را با IP‌هایشان نشان می‌دهد.
  /// این سریع‌ترین و دقیق‌ترین روش پیدا کردن تلویزیون است.
  Future<List<String>> _readArpTable() async {
    try {
      final file = File('/proc/net/arp');
      if (!await file.exists()) return [];

      final lines = (await file.readAsString()).split('\n');
      final ips = <String>[];

      for (int i = 1; i < lines.length; i++) {     // سطر اول header است
        final parts = lines[i].trim().split(RegExp(r'\s+'));
        if (parts.length < 4) continue;

        final ip = parts[0];
        final flags = parts[2];

        // 0x2 = entry کامل و فعال — دستگاه واقعاً متصل است
        // 0x6 = STALE ولی هنوز معتبر
        if ((flags == '0x2' || flags == '0x6') && !ip.startsWith('127.')) {
          ips.add(ip);
        }
      }
      return ips;
    } catch (_) {
      return [];
    }
  }

  // ── شناسایی خودکار IP تلویزیون ─────────────────────────────────────────
  /// گوشی hotspot باز می‌کند و تلویزیون به آن وصل می‌شود.
  ///
  ///  هات‌اسپات اندروید: گوشی IP = 192.168.43.1، تلویزیون IP = 192.168.43.xxx
  ///  WiFi Direct:        گوشی IP = 192.168.49.1، تلویزیون IP = 192.168.49.xxx
  ///
  ///  روش پیدا کردن IP تلویزیون:
  ///  ۱. جدول ARP خوانده می‌شود — سریع و دقیق
  ///  ۲. اگر ARP چیزی نداشت، زیرشبکه اسکن می‌شود
  Future<List<String>> detectTvIp() async {
    final candidates = <String>[];

    String? hotspotSubnet;   // زیرشبکه‌ای که گوشی روی آن hotspot است

    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;

          final parts = ip.split('.');
          if (parts.length != 4) continue;

          final lastOctet = int.tryParse(parts[3]) ?? 0;
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

          if (lastOctet == 1) {
            // گوشی خودش .1 است ⟹ گوشی hotspot است
            hotspotSubnet = subnet;
          } else {
            // گوشی client است ⟹ تلویزیون gateway است (.1)
            // (مثلاً گوشی به WiFi روتر وصل است که خود تلویزیون باشد)
            candidates.add('$subnet.1');
          }
        }
      }
    } catch (_) {}

    // ── حالت رایج: گوشی hotspot ─────────────────────────────────────────
    if (hotspotSubnet != null) {
      // اول جدول ARP — سریع‌ترین روش
      final arpIps = await _readArpTable();
      // فقط IPs همین زیرشبکه را نگه می‌داریم
      final subnetIps = arpIps.where((ip) => ip.startsWith('$hotspotSubnet.')).toList();
      candidates.addAll(subnetIps);

      // اگر ARP خالی بود، آدرس‌های DHCP رایج هات‌اسپات اندروید را اضافه کن
      if (subnetIps.isEmpty) {
        // بیشتر نسخه‌های اندروید از .2 یا .100 شروع می‌کنند
        for (int i = 2; i <= 20; i++) {
          candidates.add('$hotspotSubnet.$i');
        }
        for (int i = 100; i <= 120; i++) {
          candidates.add('$hotspotSubnet.$i');
        }
      }
    }

    // ── حالت پیش‌فرض اگر هیچ رابطی پیدا نشد ───────────────────────────
    if (candidates.isEmpty) {
      final arpIps = await _readArpTable();
      candidates.addAll(arpIps);
      // زیرشبکه رایج هات‌اسپات اندروید
      for (int i = 2; i <= 10; i++) {
        candidates.add('192.168.43.$i');
      }
      for (int i = 100; i <= 105; i++) {
        candidates.add('192.168.43.$i');
      }
    }

    return candidates.toSet().toList();
  }

  // ── اتصال خودکار (شناسایی IP + پورت) ──────────────────────────────────
  /// ابتدا IP تلویزیون را خودکار شناسایی می‌کند (از ARP یا اسکن زیرشبکه)،
  /// سپس روی همه‌ی پورت‌های معمول اتصال را به‌صورت موازی امتحان می‌کند.
  Future<bool> autoConnect() async {
    if (_state == WifiConnState.connecting) return false;
    lastError = null;
    _emit(WifiConnState.connecting);

    final ips = await detectTvIp();
    final pairs = <(String, int)>[];
    for (final ip in ips) {
      for (final port in tryPorts) {
        pairs.add((ip, port));
      }
    }

    if (pairs.isEmpty) {
      lastError = 'هیچ دستگاهی در شبکه پیدا نشد — مطمئن شوید تلویزیون به hotspot گوشی وصل است';
      _emit(WifiConnState.error);
      return false;
    }

    // همه را به‌موازات امتحان می‌کنیم — اولین موفق برنده
    final completer = Completer<(String, int)?>();
    var pending = pairs.length;

    for (final (ip, port) in pairs) {
      Socket.connect(ip, port, timeout: const Duration(milliseconds: 800))
          .then((s) {
        // socket آزمایشی را ببند — _openSocket بعداً اتصال واقعی می‌سازد
        s.destroy();
        if (!completer.isCompleted) {
          completer.complete((ip, port));
        }
      }).catchError((_) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    final result = await completer.future
        .timeout(const Duration(seconds: 5), onTimeout: () => null);

    if (result == null) {
      lastError = 'تلویزیون پیدا نشد — مطمئن شوید تلویزیون به hotspot گوشی وصل است';
      _emit(WifiConnState.error);
      return false;
    }

    return _openSocket(result.$1, result.$2);
  }

  // ── اتصال به IP دستی ────────────────────────────────────────────────────
  Future<bool> connect(String ip, {int port = 9000}) async {
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
      _emit(WifiConnState.connected);
      _startHeartbeat();

      _socket!.listen(
        (_) {},
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
        111 => 'پورت $port بسته است',
        113 => 'IP $ip در شبکه پیدا نشد',
        _   => 'خطا در اتصال (${e.osError?.errorCode})',
      };
      _emit(WifiConnState.error);
      return false;
    } on TimeoutException {
      lastError = 'مهلت اتصال تمام شد';
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => sendRaw('HEARTBEAT'),
    );
  }

  Future<void> disconnect({bool silent = false}) async {
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

  /// ارسال یک دستور خام — به انتها '\n' اضافه می‌کند
  Future<bool> sendRaw(String line) async {
    final s = _socket;
    if (s == null || _state != WifiConnState.connected) return false;
    try {
      s.write('$line\n');
      await s.flush();
      return true;
    } catch (_) {
      _cleanup();
      _emit(WifiConnState.disconnected);
      return false;
    }
  }

  Future<bool> sendKey(String key)           => sendRaw('KEY:$key');
  Future<bool> sendMouseMove(int dx, int dy) => sendRaw('MOUSE:$dx,$dy');
  Future<bool> sendMouseClick()              => sendRaw('CLICK');
}
