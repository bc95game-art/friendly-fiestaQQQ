import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ════════════════════════════════════════════════════════════════════════
//  جدول نگاشت: scanCode لینوکس (EV_KEY) → معادل HID بلوتوث
//  منبع: linux/input-event-codes.h + drivers/hid/hid-input.c + USB HID 1.12
//
//  چرا scanCode به جای keyCode؟
//  scanCode = کد خام EV_KEY لینوکس که مستقیم از سخت‌افزار IR می‌آید (استاندارد جهانی)
//  keyCode  = نگاشت اندروید که ممکن است بین دستگاه‌های مختلف فرق کند
//  ابتدا scanCode جستجو می‌شود، اگر یافت نشد keyCode اندروید به عنوان fallback
// ════════════════════════════════════════════════════════════════════════
class BtHidLookup {
  BtHidLookup._();

  // ══ جدول اول: scanCode (EV_KEY لینوکس) → HID بلوتوث ══════════════
  // این جدول برای ۹۵٪+ دکمه‌های ریموت IR پوشش دارد
  static const Map<int, _BtEntry> _scanTable = {
    // ── اصلی ──────────────────────────────────────────────────────────
    116: _BtEntry('C', 0x0030, 'power'),       // KEY_POWER
    113: _BtEntry('C', 0x00E2, 'mute'),        // KEY_MUTE
    115: _BtEntry('C', 0x00E9, 'vol_up'),      // KEY_VOLUMEUP
    114: _BtEntry('C', 0x00EA, 'vol_down'),    // KEY_VOLUMEDOWN
    402: _BtEntry('C', 0x009C, 'ch_up'),       // KEY_CHANNELUP
    403: _BtEntry('C', 0x009D, 'ch_down'),     // KEY_CHANNELDOWN
    // ── ناوبری ────────────────────────────────────────────────────────
    172: _BtEntry('C', 0x0223, 'home'),        // KEY_HOMEPAGE
    158: _BtEntry('C', 0x0224, 'back'),        // KEY_BACK
    139: _BtEntry('C', 0x0040, 'menu'),        // KEY_MENU
    174: _BtEntry('C', 0x0046, 'exit'),        // KEY_STOP → exit
    362: _BtEntry('C', 0x0046, 'exit'),        // KEY_OPTION → exit (برخی TVها)
    1:   _BtEntry('C', 0x0046, 'exit'),        // KEY_ESC → exit
    352: _BtEntry('K', 0x28,   'ok'),          // KEY_OK
    103: _BtEntry('K', 0x52,   'up'),          // KEY_UP
    108: _BtEntry('K', 0x51,   'down'),        // KEY_DOWN
    105: _BtEntry('K', 0x50,   'left'),        // KEY_LEFT
    106: _BtEntry('K', 0x4F,   'right'),       // KEY_RIGHT
    28:  _BtEntry('K', 0x28,   'return'),      // KEY_ENTER
    // ── رسانه ─────────────────────────────────────────────────────────
    164: _BtEntry('C', 0x00CD, 'play_pause'),  // KEY_PLAYPAUSE
    207: _BtEntry('C', 0x00B0, 'play'),        // KEY_PLAY
    119: _BtEntry('C', 0x00B1, 'pause'),       // KEY_PAUSE
    166: _BtEntry('C', 0x00B7, 'stop'),        // KEY_STOPCD
    174: _BtEntry('C', 0x00B7, 'stop'),        // KEY_STOP (ممکن است تکراری باشد با exit)
    168: _BtEntry('C', 0x00B4, 'rewind'),      // KEY_REWIND
    208: _BtEntry('C', 0x00B3, 'forward'),     // KEY_FASTFORWARD
    407: _BtEntry('C', 0x00B3, 'forward'),     // KEY_FORWARD
    163: _BtEntry('C', 0x00B5, 'next'),        // KEY_NEXTSONG
    177: _BtEntry('C', 0x00B5, 'next'),        // KEY_NEXT
    165: _BtEntry('C', 0x00B6, 'prev'),        // KEY_PREVIOUSSONG
    176: _BtEntry('C', 0x00B6, 'prev'),        // KEY_PREVIOUS
    167: _BtEntry('C', 0x00B2, 'record'),      // KEY_RECORD
    370: _BtEntry('C', 0x00B2, 'record'),      // KEY_PVR
    // ── اطلاعات / متا ──────────────────────────────────────────────────
    358: _BtEntry('C', 0x0060, 'info'),        // KEY_INFO
    377: _BtEntry('C', 0x0061, 'subtitle'),    // KEY_SUBTITLE
    366: _BtEntry('C', 0x008D, 'epg'),         // KEY_EPG
    378: _BtEntry('C', 0x0232, 'zoom'),        // KEY_ZOOM
    411: _BtEntry('C', 0x0160, 'text'),        // KEY_TEXT (teletext)
    // ── رنگ‌ها ─────────────────────────────────────────────────────────
    398: _BtEntry('C', 0x0069, 'color_red'),   // KEY_RED
    399: _BtEntry('C', 0x006A, 'color_green'), // KEY_GREEN
    400: _BtEntry('C', 0x006B, 'color_yellow'),// KEY_YELLOW
    401: _BtEntry('C', 0x006C, 'color_blue'),  // KEY_BLUE
    // ── منبع / صوت ────────────────────────────────────────────────────
    212: _BtEntry('C', 0x0089, 'source'),      // KEY_CAMERA (بعضی TVها برای source)
    386: _BtEntry('C', 0x0086, 'source'),      // KEY_CHANNEL → source
    393: _BtEntry('C', 0x0173, 'audio_track'), // KEY_AUDIO
    392: _BtEntry('C', 0x0173, 'audio_track'), // KEY_MEDIA (جایگزین)
    169: _BtEntry('C', 0x0040, 'menu'),        // KEY_PHONE → menu
    // ── رادیو / متفرقه TV ──────────────────────────────────────────────
    385: _BtEntry('C', 0x008D, 'radio'),       // KEY_RADIO (برخی ROM‌ها)
    419: _BtEntry('C', 0x008D, 'radio'),       // KEY_RADIO (جایگزین)
    350: _BtEntry('C', 0x0029, 'shift'),       // KEY_BOOKMARKS (برخی TVها برای shift)
    // ── اعداد (Keyboard page) ──────────────────────────────────────────
    2:   _BtEntry('K', 0x1E, 'num_1'),        // KEY_1
    3:   _BtEntry('K', 0x1F, 'num_2'),        // KEY_2
    4:   _BtEntry('K', 0x20, 'num_3'),        // KEY_3
    5:   _BtEntry('K', 0x21, 'num_4'),        // KEY_4
    6:   _BtEntry('K', 0x22, 'num_5'),        // KEY_5
    7:   _BtEntry('K', 0x23, 'num_6'),        // KEY_6
    8:   _BtEntry('K', 0x24, 'num_7'),        // KEY_7
    9:   _BtEntry('K', 0x25, 'num_8'),        // KEY_8
    10:  _BtEntry('K', 0x26, 'num_9'),        // KEY_9
    11:  _BtEntry('K', 0x27, 'num_0'),        // KEY_0
  };

  // ══ جدول دوم (fallback): keyCode اندروید → HID بلوتوث ═══════════════
  // در صورتی که scanCode در جدول بالا یافت نشد استفاده می‌شود
  static const Map<int, _BtEntry> _keyCodeTable = {
    26:  _BtEntry('C', 0x0030, 'power'),
    164: _BtEntry('C', 0x00E2, 'mute'),
    24:  _BtEntry('C', 0x00E9, 'vol_up'),
    25:  _BtEntry('C', 0x00EA, 'vol_down'),
    166: _BtEntry('C', 0x009C, 'ch_up'),
    167: _BtEntry('C', 0x009D, 'ch_down'),
    3:   _BtEntry('C', 0x0223, 'home'),
    4:   _BtEntry('C', 0x0224, 'back'),
    82:  _BtEntry('C', 0x0040, 'menu'),
    111: _BtEntry('C', 0x0046, 'exit'),
    23:  _BtEntry('K', 0x28,   'ok'),
    19:  _BtEntry('K', 0x52,   'up'),
    20:  _BtEntry('K', 0x51,   'down'),
    21:  _BtEntry('K', 0x50,   'left'),
    22:  _BtEntry('K', 0x4F,   'right'),
    66:  _BtEntry('K', 0x28,   'return'),
    85:  _BtEntry('C', 0x00CD, 'play_pause'),
    89:  _BtEntry('C', 0x00B4, 'rewind'),
    90:  _BtEntry('C', 0x00B3, 'forward'),
    87:  _BtEntry('C', 0x00B5, 'next'),
    88:  _BtEntry('C', 0x00B6, 'prev'),
    86:  _BtEntry('C', 0x00B7, 'stop'),
    130: _BtEntry('C', 0x00B2, 'record'),
    165: _BtEntry('C', 0x0060, 'info'),
    175: _BtEntry('C', 0x0061, 'subtitle'),
    172: _BtEntry('C', 0x008D, 'epg'),
    168: _BtEntry('C', 0x006D, 'zoom'),
    183: _BtEntry('C', 0x0069, 'color_red'),
    184: _BtEntry('C', 0x006A, 'color_green'),
    185: _BtEntry('C', 0x006B, 'color_yellow'),
    186: _BtEntry('C', 0x006C, 'color_blue'),
    178: _BtEntry('C', 0x0089, 'source'),
    222: _BtEntry('C', 0x0173, 'audio_track'),
    7:   _BtEntry('K', 0x27, 'num_0'),
    8:   _BtEntry('K', 0x1E, 'num_1'),
    9:   _BtEntry('K', 0x1F, 'num_2'),
    10:  _BtEntry('K', 0x20, 'num_3'),
    11:  _BtEntry('K', 0x21, 'num_4'),
    12:  _BtEntry('K', 0x22, 'num_5'),
    13:  _BtEntry('K', 0x23, 'num_6'),
    14:  _BtEntry('K', 0x24, 'num_7'),
    15:  _BtEntry('K', 0x25, 'num_8'),
    16:  _BtEntry('K', 0x26, 'num_9'),
  };

  /// اول scanCode (EV_KEY لینوکس) جستجو می‌شود، سپس keyCode اندروید به عنوان fallback
  static _BtEntry? lookup(int scanCode, int keyCode) =>
      _scanTable[scanCode] ?? _keyCodeTable[keyCode];

  static String formatUsage(int scanCode, int keyCode) {
    final e = lookup(scanCode, keyCode);
    if (e == null) return '—';
    return 'page=${e.page} usage=0x${e.usage.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }
}

class _BtEntry {
  final String page;  // 'C' یا 'K'
  final int usage;
  final String remoteKey;
  const _BtEntry(this.page, this.usage, this.remoteKey);

  Map<String, dynamic> toJson() => {
    'page': page,
    'usage': usage,
    'remoteKey': remoteKey,
  };

  static _BtEntry fromJson(Map<String, dynamic> j) =>
      _BtEntry(j['page'] as String, j['usage'] as int, j['remoteKey'] as String);
}

// ════════════════════════════════════════════════════════════════════════
//  مدل‌های داده
// ════════════════════════════════════════════════════════════════════════

/// یک رویداد کلید خام دریافتی از Kotlin
class KeyEntry {
  final String time;
  final String action;
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

  bool get looksLikeBt =>
      deviceName.toLowerCase().contains('bluetooth') ||
      deviceName.toLowerCase().contains('hid') ||
      deviceName.contains('Keyboard') ||
      source.contains('KB');

  String toLogLine() =>
      '[$time] $action  code=$keyCode ($keyName)  '
      'scan=$scanCode  src=$source  dev="$deviceName"  rep=$repeat';

  String toCsvRow() =>
      '$time,$action,$keyCode,$keyName,$scanCode,$source,$deviceId,"$deviceName",$repeat';
}

/// یک رویداد بلوتوث
class BtEvent {
  final String time;
  final String type;
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

/// یک نگاشت ضبط‌شده و پایدار (IR + BT همزمان)
class RecordedMapping {
  final int keyCode;
  final String keyName;
  final int scanCode;
  final String source;
  final String deviceName;
  final String firstSeenTime;
  final _BtEntry? btEntry;     // معادل BT HID — null اگر در جدول نباشد

  const RecordedMapping({
    required this.keyCode,
    required this.keyName,
    required this.scanCode,
    required this.source,
    required this.deviceName,
    required this.firstSeenTime,
    this.btEntry,
  });

  factory RecordedMapping.fromKeyEntry(KeyEntry e) => RecordedMapping(
        keyCode: e.keyCode,
        keyName: e.keyName,
        scanCode: e.scanCode,
        source: e.source,
        deviceName: e.deviceName,
        firstSeenTime: e.time,
        btEntry: BtHidLookup.lookup(e.scanCode, e.keyCode),
      );

  Map<String, dynamic> toJson() => {
        'keyCode': keyCode,
        'keyName': keyName,
        'scanCode': scanCode,
        'source': source,
        'deviceName': deviceName,
        'firstSeenTime': firstSeenTime,
        if (btEntry != null) 'bt': btEntry!.toJson(),
      };

  static RecordedMapping fromJson(Map<String, dynamic> j) => RecordedMapping(
        keyCode: j['keyCode'] as int,
        keyName: j['keyName'] as String,
        scanCode: j['scanCode'] as int,
        source: j['source'] as String,
        deviceName: j['deviceName'] as String,
        firstSeenTime: j['firstSeenTime'] as String,
        btEntry: j['bt'] != null
            ? _BtEntry.fromJson(j['bt'] as Map<String, dynamic>)
            : null,
      );

  String get irLabel => 'code=$keyCode  scan=$scanCode  src=$source';
  String get btLabel =>
      btEntry != null
          ? 'page=${btEntry!.page}  usage=0x${btEntry!.usage.toRadixString(16).padLeft(4, '0').toUpperCase()}  key="${btEntry!.remoteKey}"'
          : 'در جدول نگاشت نیست';

  String toShareRow() =>
      '$keyName  |  code=$keyCode  scan=$scanCode  src=$source  '
      '  BT:${btEntry != null ? "page=${btEntry!.page} usage=0x${btEntry!.usage.toRadixString(16).toUpperCase()}" : "ندارد"}'
      '  dev="$deviceName"  t=$firstSeenTime';
}

// ════════════════════════════════════════════════════════════════════════
//  لایه ذخیره‌ی دائمی
// ════════════════════════════════════════════════════════════════════════
class MappingStore {
  static const _prefKey = 'recorded_mappings_v2';

  static Future<List<RecordedMapping>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => RecordedMapping.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<RecordedMapping> mappings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(mappings.map((m) => m.toJson()).toList());
      await prefs.setString(_prefKey, encoded);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }
}

// ════════════════════════════════════════════════════════════════════════
//  صفحه اصلی
// ════════════════════════════════════════════════════════════════════════
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

  // لاگ خام
  final List<KeyEntry> _keyLog  = [];
  final List<BtEvent>  _btLog   = [];

  // نگاشت‌های ضبط‌شده — با فیلتر یکبار-برای-هر-keyCode
  final Map<int, RecordedMapping> _mappings = {};  // keyCode → mapping
  bool _loadingMappings = true;

  StreamSubscription<dynamic>? _keySub;
  StreamSubscription<dynamic>? _btSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadSavedMappings();
    _startListening();
  }

  Future<void> _loadSavedMappings() async {
    final saved = await MappingStore.load();
    if (!mounted) return;
    setState(() {
      for (final m in saved) {
        _mappings[m.keyCode] = m;
      }
      _loadingMappings = false;
    });
  }

  void _startListening() {
    _keySub = _keyChannel.receiveBroadcastStream().listen(
      (raw) {
        final entry = KeyEntry.tryParse(raw?.toString() ?? '');
        if (entry == null) return;

        // فقط رویداد DOWN را ضبط می‌کنیم (نه UP و نه تکرار)
        if (entry.action == 'DOWN' && entry.repeat == 0) {
          _processNewKeyDown(entry);
        }

        // لاگ خام همیشه ثبت می‌شود (اما تکرارها را نادیده می‌گیریم)
        if (entry.repeat == 0) {
          setState(() {
            _keyLog.insert(0, entry);
            if (_keyLog.length > 200) _keyLog.removeLast();
          });
        }
      },
      onError: (_) {},
    );

    _btSub = _btChannel.receiveBroadcastStream().listen(
      (raw) {
        final event = BtEvent.tryParse(raw?.toString() ?? '');
        if (event == null) return;
        setState(() {
          _btLog.insert(0, event);
          if (_btLog.length > 100) _btLog.removeLast();
        });
      },
      onError: (_) {},
    );
  }

  /// پردازش یک رویداد DOWN جدید: اگر تازه است → ذخیره + لرز
  void _processNewKeyDown(KeyEntry entry) {
    final isNew = !_mappings.containsKey(entry.keyCode);
    if (isNew) {
      final mapping = RecordedMapping.fromKeyEntry(entry);
      setState(() {
        _mappings[entry.keyCode] = mapping;
      });
      // ذخیره فوری در حافظه دائمی
      MappingStore.save(_mappings.values.toList());

      // لرزش هنگام ضبط دکمه جدید
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _clearMappings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('پاک کردن همه نگاشت‌ها؟',
            style: TextStyle(color: Colors.white)),
        content: const Text('این عملیات برگشت‌پذیر نیست.',
            style: TextStyle(color: Color(0xFF888888))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('پاک کن', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await MappingStore.clear();
      setState(() => _mappings.clear());
    }
  }

  Future<void> _shareMappings() async {
    if (_mappings.isEmpty) return;
    final lines = [
      'نگاشت ضبط‌شده ریموت دوو — ${DateTime.now().toString().substring(0, 16)}',
      '=' * 60,
      ..._mappings.values
          .toList()
          .map((m) => m.toShareRow()),
    ];
    await Share.share(lines.join('\n'));
  }

  Future<void> _shareKeyLog() async {
    if (_keyLog.isEmpty) return;
    final csv = [
      'time,action,keyCode,keyName,scanCode,source,deviceId,deviceName,repeat',
      ..._keyLog.map((e) => e.toCsvRow()),
    ].join('\n');
    await Share.share(csv);
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _btSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('دیاگ ریموت دوو', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.save_rounded, size: 16),
                const SizedBox(width: 6),
                Text('ضبط‌شده (${_mappings.length})'),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.list_alt_rounded, size: 16),
                const SizedBox(width: 6),
                Text('لاگ (${_keyLog.length})'),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bluetooth_rounded, size: 16),
                const SizedBox(width: 6),
                Text('بلوتوث (${_btLog.length})'),
              ]),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1A1A1A),
            onSelected: (v) {
              if (v == 'share_map')  _shareMappings();
              if (v == 'share_log')  _shareKeyLog();
              if (v == 'clear_map')  _clearMappings();
              if (v == 'clear_log')  setState(() { _keyLog.clear(); _btLog.clear(); });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share_map',  child: Text('اشتراک نگاشت‌ها')),
              PopupMenuItem(value: 'share_log',  child: Text('اشتراک لاگ CSV')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'clear_map',  child: Text('پاک‌کردن نگاشت‌ها', style: TextStyle(color: Colors.red))),
              PopupMenuItem(value: 'clear_log',  child: Text('پاک‌کردن لاگ', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MappingsTab(
            mappings: _mappings.values.toList()
              ..sort((a, b) => a.keyName.compareTo(b.keyName)),
            loading: _loadingMappings,
            onClear: _clearMappings,
            onShare: _shareMappings,
          ),
          _KeyLogTab(entries: _keyLog, onShare: _shareKeyLog),
          _BtTab(events: _btLog),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  تب ۱: نگاشت‌های ضبط‌شده (ماندگار)
// ════════════════════════════════════════════════════════════════════════
class _MappingsTab extends StatelessWidget {
  const _MappingsTab({
    required this.mappings,
    required this.loading,
    required this.onClear,
    required this.onShare,
  });

  final List<RecordedMapping> mappings;
  final bool loading;
  final VoidCallback onClear;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mappings.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sensors_rounded, size: 48, color: Color(0xFF444444)),
          const SizedBox(height: 16),
          const Text(
            'هنوز دکمه‌ای ضبط نشده',
            style: TextStyle(color: Color(0xFF666666), fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'دکمه‌های ریموت فیزیکی را فشار دهید\nهر دکمه فقط یک‌بار ضبط می‌شود',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF444444), fontSize: 13, height: 1.8),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4FC3F7).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.2)),
            ),
            child: const Text(
              'داده‌ها دائمی هستند — حتا بعد از خاموش شدن تلویزیون یا بستن اپ، نگاشت‌ها حفظ می‌شوند',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 12, height: 1.6),
            ),
          ),
        ]),
      );
    }

    return Column(
      children: [
        // راهنما
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4FC3F7).withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.18)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF4FC3F7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${mappings.length} دکمه ضبط‌شده — ماندگار در حافظه (حتا بعد از خاموشی)',
                style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12),
              ),
            ),
          ]),
        ),
        // لیست
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: mappings.length,
            itemBuilder: (_, i) => _MappingCard(mappings[i]),
          ),
        ),
      ],
    );
  }
}

class _MappingCard extends StatelessWidget {
  const _MappingCard(this.m);
  final RecordedMapping m;

  @override
  Widget build(BuildContext context) {
    final hasBt = m.btEntry != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasBt
              ? const Color(0xFF4FC3F7).withOpacity(0.35)
              : const Color(0xFF333333),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── سردستی: نام کلید + نشان BT ──────────────────────────────
        Row(children: [
          Expanded(
            child: Text(
              m.keyName,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ),
          if (hasBt)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                m.btEntry!.remoteKey,
                style: const TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF444444).withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('بدون BT',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
            ),
        ]),
        const SizedBox(height: 8),

        // ── فرمت IR ───────────────────────────────────────────────────
        _InfoRow(
          icon: Icons.settings_remote_rounded,
          label: 'IR',
          value: 'keyCode=${m.keyCode}  scanCode=${m.scanCode}  src=${m.source}',
          color: const Color(0xFFFFB74D),
        ),
        const SizedBox(height: 4),

        // ── معادل بلوتوث ──────────────────────────────────────────────
        _InfoRow(
          icon: Icons.bluetooth_rounded,
          label: 'BT HID',
          value: hasBt
              ? 'page=${m.btEntry!.page}  usage=0x${m.btEntry!.usage.toRadixString(16).padLeft(4, '0').toUpperCase()}'
              : 'نگاشت بلوتوث یافت نشد',
          color: hasBt
              ? const Color(0xFF4FC3F7)
              : const Color(0xFF555555),
        ),
        const SizedBox(height: 4),

        // ── دستگاه + زمان ─────────────────────────────────────────────
        Row(children: [
          const Icon(Icons.devices_rounded, size: 12, color: Color(0xFF555555)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${m.deviceName}   ${m.firstSeenTime}',
              style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text('$label: ',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      Expanded(
        child: Text(value,
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════
//  تب ۲: لاگ خام
// ════════════════════════════════════════════════════════════════════════
class _KeyLogTab extends StatelessWidget {
  const _KeyLogTab({required this.entries, required this.onShare});
  final List<KeyEntry> entries;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('لاگ خالی است — دکمه‌ای فشار دهید',
            style: TextStyle(color: Color(0xFF666666))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        final isNew = i == 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isNew
                ? const Color(0xFF1A2A1A)
                : const Color(0xFF121212),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isNew
                  ? Colors.green.withOpacity(0.4)
                  : const Color(0xFF222222),
            ),
          ),
          child: Row(children: [
            Text(e.time,
                style: const TextStyle(color: Color(0xFF555555), fontSize: 10)),
            const SizedBox(width: 8),
            Container(
              width: 2, height: 32,
              color: e.looksLikeBt
                  ? const Color(0xFF4FC3F7)
                  : const Color(0xFFFFB74D),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.keyName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    Text(
                      'code=${e.keyCode}  scan=${e.scanCode}  src=${e.source}',
                      style: const TextStyle(
                          color: Color(0xFF666666), fontSize: 11),
                    ),
                  ]),
            ),
            Text(e.deviceName,
                style: const TextStyle(color: Color(0xFF444444), fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  تب ۳: رویدادهای بلوتوث
// ════════════════════════════════════════════════════════════════════════
class _BtTab extends StatelessWidget {
  const _BtTab({required this.events});
  final List<BtEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bluetooth_disabled_rounded,
              size: 48, color: Color(0xFF444444)),
          SizedBox(height: 12),
          Text('هنوز رویداد بلوتوثی دریافت نشده',
              style: TextStyle(color: Color(0xFF666666))),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        final (color, icon) = switch (e.type) {
          'CONNECTED'    => (Colors.green, '🟢'),
          'DISCONNECTED' => (Colors.red, '🔴'),
          'BOND'         => (const Color(0xFF4FC3F7), '🔵'),
          _              => (const Color(0xFF888888), '⚪'),
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Row(children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.type}  ${e.extra}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    Text(
                      'دستگاه: ${e.device}  [${e.time}]',
                      style: const TextStyle(
                          color: Color(0xFF666666), fontSize: 12),
                    ),
                  ]),
            ),
          ]),
        );
      },
    );
  }
}
