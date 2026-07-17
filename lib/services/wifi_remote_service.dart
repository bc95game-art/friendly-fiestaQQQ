import 'dart:async';
import 'dart:io';

/// وضعیت اتصال وای‌فای برای نمایش در UI
enum WifiConnState { disconnected, connecting, connected, error }

/// ══════════════════════════════════════════════════════════════════════
///  WifiRemoteService — کنترل تلویزیون از طریق شبکه وای‌فای محلی
/// ══════════════════════════════════════════════════════════════════════
///
///  پروتکل: TCP socket روی پورت ۹۰۰۰ — دستورات به صورت خطوط متنی:
///    KEY:power         ← دکمه‌های کنترل
///    KEY:up / down / left / right / ok
///    KEY:back / home / menu
///    KEY:vol_up / vol_down / mute
///    KEY:ch_up / ch_down / source
///    KEY:play_pause / rewind / forward
///    MOUSE:dx,dy       ← حرکت نشانگر (مقادیر نسبی)
///    CLICK             ← کلیک چپ موس
///    HEARTBEAT         ← نگه‌داشتن اتصال زنده
///
///  نیاز TV: یک سرور ساده روی پورت ۹۰۰۰ که این دستورات را به
///  رویداد کلید اندروید ترجمه کند. مثال پایتون در README توضیح داده شده.
class WifiRemoteService {
  WifiRemoteService._();
  static final WifiRemoteService instance = WifiRemoteService._();

  static const defaultPort = 9000;

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

  String? lastError;

  void _emit(WifiConnState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  /// اتصال به IP و پورت مشخص‌شده
  Future<bool> connect(String ip, {int port = defaultPort}) async {
    if (_state == WifiConnState.connecting) return false;

    await disconnect(silent: true);
    lastError = null;
    _emit(WifiConnState.connecting);

    try {
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _connectedIp = ip;
      _connectedPort = port;
      _emit(WifiConnState.connected);
      _startHeartbeat();

      _socket!.listen(
        (_) {},
        onError: (e) {
          lastError = 'اتصال قطع شد';
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
        111 => 'تلویزیون این پورت را نمی‌پذیرد — سرور را بررسی کنید',
        113 => 'دستگاه در شبکه پیدا نشد — IP را بررسی کنید',
        _ => 'خطا در اتصال: ${e.message}',
      };
      _emit(WifiConnState.error);
      return false;
    } on TimeoutException {
      lastError = 'مدت انتظار تمام شد — IP یا پورت را بررسی کنید';
      _emit(WifiConnState.error);
      return false;
    } catch (e) {
      lastError = 'خطای ناشناخته: $e';
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
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _connectedIp = null;
    _connectedPort = null;
    if (!silent && _state != WifiConnState.disconnected) {
      _emit(WifiConnState.disconnected);
    }
  }

  /// ارسال یک خط دستور خام (بدون '\n' در انتها — خودش اضافه می‌کند)
  Future<bool> sendRaw(String line) async {
    final s = _socket;
    if (s == null || _state != WifiConnState.connected) return false;
    try {
      s.write('$line\n');
      await s.flush();
      return true;
    } catch (_) {
      lastError = 'ارتباط قطع شد';
      _cleanup();
      _emit(WifiConnState.disconnected);
      return false;
    }
  }

  Future<bool> sendKey(String key)              => sendRaw('KEY:$key');
  Future<bool> sendMouseMove(int dx, int dy)    => sendRaw('MOUSE:$dx,$dy');
  Future<bool> sendMouseClick()                 => sendRaw('CLICK');

  // ── اسکن شبکه برای یافتن تلویزیون‌های سازگار ─────────────────────────
  /// شبکه محلی را اسکن می‌کند تا دستگاه‌هایی که پورت ۹۰۰۰ باز دارند
  /// پیدا کند. چون به همه آدرس‌ها وصل نمی‌شویم (خیلی طول می‌کشد)،
  /// فقط آدرس‌های رایج (.1 تا .20 و .100 تا .115 و .200+) بررسی می‌شود.
  Future<List<String>> discover({int port = defaultPort}) async {
    final found = <String>[];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final futures = <Future>[];
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4 || parts[0] == '127') continue;
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

          // آدرس‌های متداول روتر/TV: ۱–۲۰، ۱۰۰–۱۲۰، ۱۵۰–۱۷۰، ۲۰۰–۲۵۴
          final last = [
            ...List.generate(20, (i) => i + 1),
            ...List.generate(21, (i) => i + 100),
            ...List.generate(21, (i) => i + 150),
            ...List.generate(55, (i) => i + 200),
          ];

          for (final l in last) {
            final ip = '$subnet.$l';
            futures.add(
              Socket.connect(ip, port,
                      timeout: const Duration(milliseconds: 500))
                  .then((s) {
                s.destroy();
                found.add(ip);
              }).catchError((_) {}),
            );
          }
        }
      }
      await Future.wait(futures);
    } catch (_) {}
    found.sort();
    return found;
  }
}
