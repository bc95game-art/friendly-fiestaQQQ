import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای برای نمایش در UI
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق وای‌فای محلی
/// ══════════════════════════════════════════════════════════════════════
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
///
///  وقتی تلویزیون نقطه‌ی اتصال WiFi است (مثل گوشی)، IP آن معمولاً
///  همان گتوی شبکه است — متد [detectTvIp] آن را خودکار پیدا می‌کند.
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

  // ── شناسایی خودکار IP تلویزیون ─────────────────────────────────────────
  /// وقتی تلویزیون به‌عنوان نقطه‌ی اتصال WiFi عمل می‌کند (مانند هات‌اسپات
  /// گوشی)، IP آن معمولاً همان آدرس گتوی شبکه‌ی گوشی است:
  ///   - هات‌اسپات اندروید استاندارد: 192.168.43.1
  ///   - WiFi Direct اندروید:         192.168.49.1
  ///   - هات‌اسپات iOS:               172.20.10.1
  ///   - سایر حالت‌ها: اولین آدرس subnet (.1)
  Future<List<String>> detectTvIp() async {
    final candidates = <String>[];
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

          // هات‌اسپات اندروید استاندارد
          if (ip.startsWith('192.168.43.')) {
            candidates.insert(0, '192.168.43.1');
          }
          // WiFi Direct
          else if (ip.startsWith('192.168.49.')) {
            candidates.insert(0, '192.168.49.1');
          }
          // هات‌اسپات iOS
          else if (ip.startsWith('172.20.10.')) {
            candidates.insert(0, '172.20.10.1');
          }
          // سایر شبکه‌ها — گتوی احتمالی = .1
          else {
            candidates.add('${parts[0]}.${parts[1]}.${parts[2]}.1');
          }
        }
      }
    } catch (_) {}

    // اگر هیچ رابطی پیدا نشد، مقادیر پیش‌فرض را برگردان
    if (candidates.isEmpty) {
      candidates.addAll(['192.168.43.1', '192.168.49.1', '192.168.1.1']);
    }

    return candidates.toSet().toList(); // حذف تکراری‌ها
  }

  // ── اتصال خودکار (شناسایی IP + پورت) ──────────────────────────────────
  /// ابتدا IP تلویزیون را خودکار شناسایی می‌کند، سپس روی همه‌ی پورت‌های
  /// معمول اتصال را امتحان می‌کند. اولین اتصال موفق برنده می‌شود.
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

    // همه را به‌موازات امتحان می‌کنیم — اولین موفق برنده
    final completer = Completer<(String, int)?>();
    var pending = pairs.length;

    for (final (ip, port) in pairs) {
      Socket.connect(ip, port, timeout: const Duration(milliseconds: 800))
          .then((s) {
        // ⚠️ رفع باگ «نشت Socket»: socket آزمایشی را همیشه ببند —
        // اگر برنده باشد _openSocket() بعداً اتصال واقعی می‌سازد،
        // اگر بازنده باشد هم باید بسته شود. بدون این، تلویزیون دو
        // اتصال همزمان می‌دید (آزمایش + واقعی).
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
      lastError = 'تلویزیون پیدا نشد — مطمئن شوید گوشی به WiFi تلویزیون وصل است';
      _emit(WifiConnState.error);
      return false;
    }

    return _openSocket(result.$1, result.$2);
  }

  // ── اتصال به IP دستی ────────────────────────────────────────────────────
  /// به IP و پورت دستی مشخص‌شده متصل می‌شود.
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
