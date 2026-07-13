import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const TvDiagnosticApp());

class TvDiagnosticApp extends StatelessWidget {
  const TvDiagnosticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دیاگ ریموت دوو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4FC3F7),
          secondary: const Color(0xFFFFB74D),
          surface: const Color(0xFF1A1A1A),
        ),
        tabBarTheme: const TabBarTheme(
          labelColor: Color(0xFF4FC3F7),
          unselectedLabelColor: Color(0xFF888888),
          indicatorColor: Color(0xFF4FC3F7),
        ),
      ),
      home: const DiagnosticScreen(),
    );
  }
}

// ── مدل یک رویداد کلید ──────────────────────────────────────────────────────
class KeyEntry {
  final String time;
  final String action;   // DOWN / UP
  final int keyCode;
  final String keyName;
  final int scanCode;
  final String source;
  final int deviceId;
  final String deviceName;
  final int repeat;

  const KeyEntry({
    required this.time,
    required this.action,
    required this.keyCode,
    required this.keyName,
    required this.scanCode,
    required this.source,
    required this.deviceId,
    required this.deviceName,
    required this.repeat,
  });

  /// فرمت pipe-separated که از Kotlin می‌آید:
  /// time|action|keyCode|keyName|scanCode|source|deviceId|deviceName|repeat
  static KeyEntry? tryParse(String raw) {
    final p = raw.split('|');
    if (p.length < 9) return null;
    return KeyEntry(
      time: p[0],
      action: p[1],
      keyCode: int.tryParse(p[2]) ?? 0,
      keyName: p[3],
      scanCode: int.tryParse(p[4]) ?? 0,
      source: p[5],
      deviceId: int.tryParse(p[6]) ?? 0,
      deviceName: p[7],
      repeat: int.tryParse(p[8]) ?? 0,
    );
  }

  /// آیا شبیه رویداد از دستگاه بلوتوث است؟
  bool get looksLikeBt =>
      deviceName.toLowerCase().contains('bluetooth') ||
      deviceName.toLowerCase().contains('hid') ||
      deviceName.contains('Keyboard') ||
      source.contains('KB');

  /// کلید یکتا برای جدول نگاشت (keyCode + scanCode + deviceId)
  String get mappingKey => '$keyCode:$scanCode:$deviceId';

  String toLogLine() =>
      '[$time] $action  code=$keyCode ($keyName)  '
      'scan=$scanCode  src=$source  dev="$deviceName"  rep=$repeat';

  String toCsvRow() =>
      '$time,$action,$keyCode,$keyName,$scanCode,$source,$deviceId,"$deviceName",$repeat';
}

// ── مدل رویداد بلوتوث ───────────────────────────────────────────────────────
class BtEvent {
  final String time;
  final String type;   // CONNECTED / DISCONNECTED / BOND
  final String device;
  final String extra;

  const BtEvent({required this.time, required this.type, required this.device, this.extra = ''});

  static BtEvent? tryParse(String raw) {
    final p = raw.split('|');
    if (p.length < 2) return null;
    return BtEvent(
      time: p[0],
      type: p[1],
      device: p.length > 2 ? p[2] : '?',
      extra: p.length > 3 ? p[3] : '',
    );
  }
}

// ── صفحه اصلی ───────────────────────────────────────────────────────────────
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen>
    with SingleTickerProviderStateMixin {
  static const _keyChannel = EventChannel('daewoo_tv_diag/keys');
  static const _btChannel  = EventChannel('daewoo_tv_diag/bt');

  late final TabController _tabs;

  // لاگ کامل
  final List<KeyEntry> _keyLog = [];
  final List<BtEvent>  _btLog  = [];

  // جدول نگاشت: فقط اولین DOWN هر (keyCode, scanCode, device) یکتا
  final Map<String, KeyEntry> _mappingTable = {};

  // فیلترها
  bool _showUpEvents = false;   // پیش‌فرض: فقط DOWN نشان بده
  bool _showRepeat   = false;   // پیش‌فرض: تکرار پنهان

  StreamSubscription? _keySub;
  StreamSubscription? _btSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);

    _keySub = _keyChannel.receiveBroadcastStream().listen((raw) {
      final entry = KeyEntry.tryParse(raw.toString());
      if (entry == null) return;
      setState(() {
        _keyLog.insert(0, entry);
        if (_keyLog.length > 1000) _keyLog.removeLast();
        // جدول نگاشت: فقط اولین DOWN بدون تکرار
        if (entry.action == 'DOWN' && entry.repeat == 0) {
          _mappingTable.putIfAbsent(entry.mappingKey, () => entry);
        }
      });
    });

    _btSub = _btChannel.receiveBroadcastStream().listen((raw) {
      final ev = BtEvent.tryParse(raw.toString());
      if (ev == null) return;
      setState(() {
        _btLog.insert(0, ev);
        if (_btLog.length > 200) _btLog.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _btSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ── اشتراک‌گذاری ────────────────────────────────────────────────────────
  Future<void> _shareLog() async {
    final buf = StringBuffer('=== لاگ کامل کلیدها ===\n');
    for (final e in _keyLog.reversed) {
      buf.writeln(e.toLogLine());
    }
    buf.writeln('\n=== جدول نگاشت یکتا ===');
    buf.writeln('keyCode,keyName,scanCode,source,deviceId,deviceName');
    for (final e in _mappingTable.values) {
      buf.writeln('${e.keyCode},${e.keyName},${e.scanCode},${e.source},${e.deviceId},"${e.deviceName}"');
    }
    await Share.share(buf.toString(), subject: 'نگاشت کلید ریموت دوو');
  }

  Future<void> _shareMappingCsv() async {
    final buf = StringBuffer('keyCode,keyName,scanCode,source,deviceId,deviceName\n');
    for (final e in _mappingTable.values) {
      buf.writeln('${e.keyCode},${e.keyName},${e.scanCode},${e.source},${e.deviceId},"${e.deviceName}"');
    }
    await Share.share(buf.toString(), subject: 'جدول نگاشت HID دوو.csv');
  }

  void _clearAll() => setState(() {
    _keyLog.clear();
    _btLog.clear();
    _mappingTable.clear();
  });

  // ── ساخت UI ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('دیاگ ریموت دوو', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${_keyLog.length} رویداد  |  ${_mappingTable.length} کلید یکتا  |  ${_btLog.length} BT',
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
            ),
          ],
        ),
        actions: [
          // فیلتر UP/DOWN
          Tooltip(
            message: _showUpEvents ? 'پنهان کردن UP' : 'نمایش UP',
            child: IconButton(
              icon: Icon(
                _showUpEvents ? Icons.unfold_less : Icons.unfold_more,
                color: _showUpEvents ? const Color(0xFF4FC3F7) : Colors.grey,
              ),
              onPressed: () => setState(() => _showUpEvents = !_showUpEvents),
            ),
          ),
          Tooltip(
            message: 'ارسال لاگ',
            child: IconButton(icon: const Icon(Icons.ios_share), onPressed: _shareLog),
          ),
          Tooltip(
            message: 'پاک کردن همه',
            child: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearAll),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '⌨️ لاگ کلیدها'),
            Tab(text: '📊 جدول نگاشت'),
            Tab(text: '📶 بلوتوث'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildKeyLog(),
          _buildMappingTable(),
          _buildBtLog(),
        ],
      ),
    );
  }

  // ── تب ۱: لاگ کامل کلیدها ───────────────────────────────────────────────
  Widget _buildKeyLog() {
    final entries = _keyLog.where((e) {
      if (!_showUpEvents && e.action == 'UP') return false;
      if (!_showRepeat && e.repeat > 0) return false;
      return true;
    }).toList();

    if (entries.isEmpty) {
      return _emptyHint(
        '⌨️',
        'منتظر ورودی...',
        'دکمه‌های ریموت گوشی یا ریموت اصلی را بزنید.\n'
        'هر کلیدی که تلویزیون دریافت کند اینجا ظاهر می‌شود.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _KeyEventTile(entry: entries[i]),
    );
  }

  // ── تب ۲: جدول نگاشت یکتا ──────────────────────────────────────────────
  Widget _buildMappingTable() {
    final rows = _mappingTable.values.toList();

    return Column(
      children: [
        // هدر راهنما
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A2A1A),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF81C784), size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'هر دکمه گوشی را یک‌بار بزنید — یکتاها اینجا جمع می‌شوند.',
                  style: TextStyle(color: Color(0xFF81C784), fontSize: 12),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('CSV', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF4FC3F7)),
                onPressed: rows.isEmpty ? null : _shareMappingCsv,
              ),
            ],
          ),
        ),
        // هدر ستون‌ها
        if (rows.isNotEmpty)
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: const [
                Expanded(flex: 2, child: _ColHeader('کد اندروید')),
                Expanded(flex: 3, child: _ColHeader('نام کلید')),
                Expanded(flex: 2, child: _ColHeader('scanCode')),
                Expanded(flex: 2, child: _ColHeader('منبع')),
                Expanded(flex: 3, child: _ColHeader('دستگاه')),
              ],
            ),
          ),
        // ردیف‌ها
        Expanded(
          child: rows.isEmpty
              ? _emptyHint('📊', 'جدول خالی است',
                  'هنوز هیچ دکمه‌ای زده نشده.\nبرو تب لاگ و دکمه‌ها را بزن.')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFF2A2A2A)),
                  itemBuilder: (ctx, i) => _MappingRow(entry: rows[i]),
                ),
        ),
      ],
    );
  }

  // ── تب ۳: رویدادهای بلوتوث ──────────────────────────────────────────────
  Widget _buildBtLog() {
    if (_btLog.isEmpty) {
      return _emptyHint(
        '📶',
        'رویداد بلوتوثی نیامده',
        'وقتی گوشی از طریق HID بلوتوث متصل یا قطع شود اینجا نشان داده می‌شود.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _btLog.length,
      itemBuilder: (ctx, i) => _BtEventTile(event: _btLog[i]),
    );
  }

  Widget _emptyHint(String icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFCCCCCC))),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF888888))),
          ],
        ),
      ),
    );
  }
}

// ── ردیف رویداد کلید در لاگ ─────────────────────────────────────────────────
class _KeyEventTile extends StatelessWidget {
  final KeyEntry entry;
  const _KeyEventTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDown = entry.action == 'DOWN';
    final isBt   = entry.looksLikeBt;
    final accentColor = isBt ? const Color(0xFF4FC3F7) : const Color(0xFFFFB74D);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Row(
        children: [
          // آیکون DOWN/UP
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDown ? accentColor.withAlpha(40) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                isDown ? '▼' : '▲',
                style: TextStyle(
                  color: isDown ? accentColor : const Color(0xFF555555),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // خط اصلی: نام کلید + کدها
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                    children: [
                      TextSpan(
                        text: entry.keyName.replaceFirst('KEYCODE_', ''),
                        style: TextStyle(
                          color: isDown ? Colors.white : const Color(0xFF666666),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: '  #${entry.keyCode}',
                        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 13),
                      ),
                      TextSpan(
                        text: '  scan=${entry.scanCode}',
                        style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                // خط دوم: دستگاه + زمان
                Text(
                  '${isBt ? "🔵 BT" : "🔴 IR/SYS"}  ${entry.deviceName}  [${entry.time}]',
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // کپی
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: entry.toLogLine()));
            },
            child: const Icon(Icons.copy, size: 16, color: Color(0xFF444444)),
          ),
        ],
      ),
    );
  }
}

// ── ردیف جدول نگاشت ──────────────────────────────────────────────────────────
class _MappingRow extends StatelessWidget {
  final KeyEntry entry;
  const _MappingRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isBt = entry.looksLikeBt;
    return GestureDetector(
      onTap: () {
        // کپی ردیف CSV با یک ضربه
        Clipboard.setData(ClipboardData(
          text: '${entry.keyCode},${entry.keyName},${entry.scanCode},${entry.source},${entry.deviceId},"${entry.deviceName}"',
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('کپی شد'),
            duration: Duration(milliseconds: 800),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: Colors.transparent,
        child: Row(
          children: [
            // keyCode
            Expanded(
              flex: 2,
              child: Text(
                '${entry.keyCode}',
                style: TextStyle(
                  color: isBt ? const Color(0xFF4FC3F7) : const Color(0xFFFFB74D),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            // keyName (بدون پیشوند KEYCODE_)
            Expanded(
              flex: 3,
              child: Text(
                entry.keyName.replaceFirst('KEYCODE_', ''),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // scanCode
            Expanded(
              flex: 2,
              child: Text(
                '${entry.scanCode}\n0x${entry.scanCode.toRadixString(16).toUpperCase()}',
                style: const TextStyle(
                  color: Color(0xFFFFB74D),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            // source
            Expanded(
              flex: 2,
              child: Text(
                entry.source,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
            // deviceName (کوتاه)
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Text(
                    isBt ? '🔵' : '🔴',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.deviceName,
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ردیف رویداد بلوتوث ──────────────────────────────────────────────────────
class _BtEventTile extends StatelessWidget {
  final BtEvent event;
  const _BtEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.type) {
      'CONNECTED'    => ('🔗', const Color(0xFF81C784)),
      'DISCONNECTED' => ('❌', const Color(0xFFE57373)),
      'BOND'         => ('🔄', const Color(0xFFFFB74D)),
      _ => ('•', Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.type}  ${event.extra}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'دستگاه: ${event.device}  [${event.time}]',
                  style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── هدر ستون جدول ───────────────────────────────────────────────────────────
class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF888888),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}
