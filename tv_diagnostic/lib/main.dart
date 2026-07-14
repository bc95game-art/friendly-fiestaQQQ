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

// ════════════════════════════════════════════════════════════════════════
//  فهرست کامل توابع استاندارد ریموت — برای انتخاب دستیِ کد بلوتوث
//
//  چرا لازم است؟ بعضی دکمه‌های فیزیکیِ ریموت (مثل EXIT، RADIO، ZOOM، TEXT،
//  AUDIO، SUB.T روی این ریموت خاص) یک اسکن‌کد اختصاصیِ همان برند/مدل تلویزیون
//  تولید می‌کنند که در جدول‌های بالا (که فقط کدهای رایج لینوکس/اندروید را
//  پوشش می‌دهند) وجود ندارد. در این حالت دکمه با موفقیت به‌عنوان IR ضبط
//  می‌شود، اما نگاشت خودکار بلوتوث برایش پیدا نمی‌شود. تنها راه، دانستنِ
//  عملکرد واقعیِ دکمه (توسط کسی که آن را فشار می‌دهد) و انتخاب دستیِ معادل
//  آن از این فهرست است — که سپس برای همیشه ذخیره می‌شود.
// ════════════════════════════════════════════════════════════════════════
const List<_BtEntry> _manualBtChoices = [
  _BtEntry('C', 0x0030, 'power'),
  _BtEntry('C', 0x00E2, 'mute'),
  _BtEntry('C', 0x00E9, 'vol_up'),
  _BtEntry('C', 0x00EA, 'vol_down'),
  _BtEntry('C', 0x009C, 'ch_up'),
  _BtEntry('C', 0x009D, 'ch_down'),
  _BtEntry('C', 0x0223, 'home'),
  _BtEntry('C', 0x0224, 'back'),
  _BtEntry('C', 0x0040, 'menu'),
  _BtEntry('C', 0x0046, 'exit'),
  _BtEntry('K', 0x28, 'ok'),
  _BtEntry('K', 0x52, 'up'),
  _BtEntry('K', 0x51, 'down'),
  _BtEntry('K', 0x50, 'left'),
  _BtEntry('K', 0x4F, 'right'),
  _BtEntry('K', 0x28, 'return'),
  _BtEntry('C', 0x00CD, 'play_pause'),
  _BtEntry('C', 0x00B0, 'play'),
  _BtEntry('C', 0x00B1, 'pause'),
  _BtEntry('C', 0x00B7, 'stop'),
  _BtEntry('C', 0x00B4, 'rewind'),
  _BtEntry('C', 0x00B3, 'forward'),
  _BtEntry('C', 0x00B5, 'next'),
  _BtEntry('C', 0x00B6, 'prev'),
  _BtEntry('C', 0x00B2, 'record'),
  _BtEntry('C', 0x0060, 'info'),
  _BtEntry('C', 0x0061, 'subtitle'),
  _BtEntry('C', 0x008D, 'epg'),
  _BtEntry('C', 0x0232, 'zoom'),
  _BtEntry('C', 0x0160, 'text'),
  _BtEntry('C', 0x0069, 'color_red'),
  _BtEntry('C', 0x006A, 'color_green'),
  _BtEntry('C', 0x006B, 'color_yellow'),
  _BtEntry('C', 0x006C, 'color_blue'),
  _BtEntry('C', 0x0089, 'source'),
  _BtEntry('C', 0x0173, 'audio_track'),
  _BtEntry('C', 0x008D, 'radio'),
  _BtEntry('C', 0x0029, 'shift'),
  _BtEntry('K', 0x1E, 'num_1'),
  _BtEntry('K', 0x1F, 'num_2'),
  _BtEntry('K', 0x20, 'num_3'),
  _BtEntry('K', 0x21, 'num_4'),
  _BtEntry('K', 0x22, 'num_5'),
  _BtEntry('K', 0x23, 'num_6'),
  _BtEntry('K', 0x24, 'num_7'),
  _BtEntry('K', 0x25, 'num_8'),
  _BtEntry('K', 0x26, 'num_9'),
  _BtEntry('K', 0x27, 'num_0'),
];

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
  final _BtEntry? btEntry;
  /// اگر true باشد این دکمه توسط سیستم اندروید قطع می‌شود
  /// و قابل ضبط نیست — کدش از استاندارد USB HID شناخته‌شده است
  final bool isSystemButton;

  const RecordedMapping({
    required this.keyCode,
    required this.keyName,
    required this.scanCode,
    required this.source,
    required this.deviceName,
    required this.firstSeenTime,
    this.btEntry,
    this.isSystemButton = false,
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
        if (isSystemButton) 'sys': true,
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
        isSystemButton: (j['sys'] as bool?) ?? false,
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

/// کلید یکتای نگاشت — بر اساس ترکیب keyCode+scanCode، نه فقط keyCode.
///
/// چرا؟ دکمه‌هایی که اندروید نمی‌تواند بشناسد همه با keyCode=0
/// (KEYCODE_UNKNOWN) گزارش می‌شوند، اما scanCode واقعی‌شان با هم فرق دارد
/// (هر دکمه‌ی فیزیکی روی ریموت یک scanCode خاص خودش را می‌فرستد). اگر فقط
/// از keyCode به‌عنوان کلید استفاده می‌شد، دومین دکمه‌ی «ناشناخته» که فشار
/// داده می‌شد اصلاً ثبت نمی‌شد — چون از نظر برنامه، keyCode آن (=۰) از قبل
/// «ضبط‌شده» به‌حساب می‌آمد. همین چیزی بود که باعث می‌شد چند دکمه‌ی فیزیکیِ
/// متفاوت روی ریموت، هرگز در تب «ضبط‌شده» ظاهر نشوند.
String _mapKey(int keyCode, int scanCode) => '${keyCode}_$scanCode';

// ════════════════════════════════════════════════════════════════════════
//  دکمه‌های سیستمی از پیش تعریف‌شده
//  این دکمه‌ها را سیستم اندروید قبل از رسیدن به اپ می‌گیرد:
//  POWER → سیستم را خاموش می‌کند، هیچ اپی نمی‌تواند آن را ببیند
//  کدهای BT HID از استاندارد USB HID 1.12 گرفته شده و صحیح هستند
// ════════════════════════════════════════════════════════════════════════
const _builtInSystemButtons = <int, RecordedMapping>{
  26: RecordedMapping(
    keyCode: 26,
    keyName: 'KEYCODE_POWER',
    scanCode: 116,
    source: 'SYS',
    deviceName: 'سیستم — قابل ضبط نیست',
    firstSeenTime: '—',
    isSystemButton: true,
    btEntry: _BtEntry('C', 0x0030, 'power'),
  ),
};

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

  // نگاشت‌های ضبط‌شده — با فیلتر یکبار-برای-هر-دکمه (کلید = keyCode+scanCode)
  final Map<String, RecordedMapping> _mappings = {};
  bool _loadingMappings = true;

  // وضعیت سرویس دسترسی‌پذیری (برای گرفتن HOME/VOLUME/MUTE واقعی)
  static const _a11yChannel = MethodChannel('daewoo_tv_diag/a11y');
  bool _a11yEnabled = false;

  StreamSubscription<dynamic>? _keySub;
  StreamSubscription<dynamic>? _btSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadSavedMappings();
    _startListening();
    _checkA11yStatus();
  }

  Future<void> _loadSavedMappings() async {
    final saved = await MappingStore.load();
    if (!mounted) return;
    setState(() {
      // اول دکمه‌های سیستمی ثابت را اضافه کن
      for (final m in _builtInSystemButtons.values) {
        _mappings[_mapKey(m.keyCode, m.scanCode)] = m;
      }
      // سپس دکمه‌های ضبط‌شده (اگر capture شدند جایگزین می‌شوند)
      for (final m in saved) {
        _mappings[_mapKey(m.keyCode, m.scanCode)] = m;
      }
      _loadingMappings = false;
    });
  }

  /// آیا کاربر سرویس دسترسی‌پذیری را برای گرفتن دکمه‌های سیستمی
  /// (HOME واقعی، VOLUME، MUTE) فعال کرده است؟
  Future<void> _checkA11yStatus() async {
    try {
      final enabled = await _a11yChannel.invokeMethod<bool>('isEnabled') ?? false;
      if (!mounted) return;
      setState(() => _a11yEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _openA11ySettings() async {
    try {
      await _a11yChannel.invokeMethod('openSettings');
    } catch (_) {}
    // کاربر باید خودش سرویس را در آن صفحه فعال کند؛ چند لحظه بعد از
    // برگشت به اپ وضعیت را دوباره بررسی می‌کنیم (در didChangeAppLifecycleState
    // نیست، پس فقط با یک تأخیر کوتاه یک‌بار دوباره چک می‌کنیم).
    Future.delayed(const Duration(seconds: 2), _checkA11yStatus);
  }

  void _startListening() {
    _keySub = _keyChannel.receiveBroadcastStream().listen(
      (raw) {
        final entry = KeyEntry.tryParse(raw?.toString() ?? '');
        if (entry == null) return;

        // رویداد ویژه: فشار اول BACK — نمایش راهنما
        if (entry.action == 'BACK_BLOCKED') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                'BACK ضبط شد ✓  —  دوباره فشار دهید برای بازگشت',
                textAlign: TextAlign.center,
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF2A2A2A),
            ));
          }
          return;
        }

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
    final key = _mapKey(entry.keyCode, entry.scanCode);
    final isNew = !_mappings.containsKey(key);
    if (isNew) {
      final mapping = RecordedMapping.fromKeyEntry(entry);
      setState(() {
        _mappings[key] = mapping;
      });
      // ذخیره فوری در حافظه دائمی
      MappingStore.save(_mappings.values.toList());

      // لرزش هنگام ضبط دکمه جدید
      HapticFeedback.mediumImpact();
    }
  }

  /// نسبت‌دادن دستیِ کد بلوتوث به یک دکمه که نگاشت خودکار برایش پیدا نشد.
  void _assignManualBt(RecordedMapping m, _BtEntry entry) {
    final key = _mapKey(m.keyCode, m.scanCode);
    final updated = RecordedMapping(
      keyCode: m.keyCode,
      keyName: m.keyName,
      scanCode: m.scanCode,
      source: m.source,
      deviceName: m.deviceName,
      firstSeenTime: m.firstSeenTime,
      btEntry: entry,
      isSystemButton: m.isSystemButton,
    );
    setState(() {
      _mappings[key] = updated;
    });
    MappingStore.save(_mappings.values.toList());
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('کد بلوتوث «${entry.remoteKey}» به «${m.keyName}» نسبت داده شد ✓'),
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF1A2A1A),
    ));
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
      setState(() {
        _mappings.clear();
        // دکمه‌های سیستمی همیشه باید باقی بمانند
        for (final m in _builtInSystemButtons.values) {
          _mappings[_mapKey(m.keyCode, m.scanCode)] = m;
        }
      });
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
            onAssign: _assignManualBt,
            a11yEnabled: _a11yEnabled,
            onOpenA11ySettings: _openA11ySettings,
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
    required this.onAssign,
    required this.a11yEnabled,
    required this.onOpenA11ySettings,
  });

  final List<RecordedMapping> mappings;
  final bool loading;
  final VoidCallback onClear;
  final VoidCallback onShare;
  final void Function(RecordedMapping, _BtEntry) onAssign;
  final bool a11yEnabled;
  final VoidCallback onOpenA11ySettings;

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
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
        // بنر سرویس دسترسی‌پذیری — برای دکمه‌هایی که اصلاً توسط اپ دیده
        // نمی‌شوند (HOME واقعی، VOLUME +/-، بی‌صدا) چون اندروید آن‌ها را
        // قبل از رسیدن به هر اپ مصرف می‌کند.
        if (!a11yEnabled)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A65).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFF8A65).withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFFF8A65)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'دکمه‌هایی مثل HOME واقعی، ولوم و بی‌صدا اصلاً دیده نمی‌شوند',
                    style: TextStyle(color: Color(0xFFFF8A65), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'این دکمه‌ها را خودِ اندروید قبل از رسیدن به هر اپ مصرف می‌کند. با فعال‌کردن «سرویس دسترسی‌پذیری» می‌توان آن‌ها را هم دید و ضبط کرد.',
                style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenA11ySettings,
                  icon: const Icon(Icons.accessibility_new_rounded, size: 16),
                  label: const Text('باز کردن تنظیمات دسترسی‌پذیری'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A65),
                    side: const BorderSide(color: Color(0xFFFF8A65)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ]),
          ),
        // لیست
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: mappings.length,
            itemBuilder: (_, i) => _MappingCard(mappings[i], onAssign: onAssign),
          ),
        ),
      ],
    );
  }
}

class _MappingCard extends StatelessWidget {
  const _MappingCard(this.m, {required this.onAssign});
  final RecordedMapping m;
  final void Function(RecordedMapping, _BtEntry) onAssign;

  Future<void> _pickManualBt(BuildContext context) async {
    final chosen = await showModalBottomSheet<_BtEntry>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      builder: (_) => _BtPickerSheet(keyName: m.keyName),
    );
    if (chosen != null) onAssign(m, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final hasBt = m.btEntry != null;
    final isSys = m.isSystemButton;
    // رنگ border: نارنجی = سیستمی، آبی = BT دارد، خاکستری = بدون BT
    final borderColor = isSys
        ? const Color(0xFFFF8A65).withOpacity(0.45)
        : hasBt
            ? const Color(0xFF4FC3F7).withOpacity(0.35)
            : const Color(0xFF333333);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── سردستی: نام کلید + نشان‌ها ──────────────────────────────
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
          // نشان سیستمی (اول — اگر هست)
          if (isSys) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A65).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('🔒 سیستمی',
                  style: TextStyle(
                      color: Color(0xFFFF8A65),
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
          ],
          // نشان BT
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
          else if (!isSys)
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

        // توضیح برای دکمه سیستمی
        if (isSys) ...[
          const SizedBox(height: 6),
          const Text(
            'این دکمه توسط سیستم اندروید قبل از رسیدن به اپ قطع می‌شود.\nکد BT HID از استاندارد USB HID شناخته‌شده و صحیح است.',
            style: TextStyle(color: Color(0xFFFF8A65), fontSize: 11, height: 1.5),
          ),
        ],

        const SizedBox(height: 8),

        // ── فرمت IR ───────────────────────────────────────────────────
        _InfoRow(
          icon: Icons.settings_remote_rounded,
          label: 'IR',
          value: isSys
              ? 'keyCode=${m.keyCode}  scanCode=${m.scanCode}  (استاندارد — بدون ضبط)'
              : 'keyCode=${m.keyCode}  scanCode=${m.scanCode}  src=${m.source}',
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

        // ── انتخاب دستیِ کد بلوتوث — فقط وقتی نگاشت خودکار پیدا نشد ────
        if (!hasBt && !isSys) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickManualBt(context),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('انتخاب دستی کد بلوتوث'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4FC3F7),
                side: const BorderSide(color: Color(0xFF4FC3F7)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  شیت انتخاب دستیِ عملکرد یک دکمه — وقتی نگاشت خودکار پیدا نشود
// ════════════════════════════════════════════════════════════════════════
class _BtPickerSheet extends StatelessWidget {
  const _BtPickerSheet({required this.keyName});
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF444444),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('عملکرد واقعی «$keyName» چیست؟',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              const Text(
                'اندروید نتوانست این دکمه را با کلید شناخته‌شده‌ای تطبیق دهد، بنابراین کد بلوتوث آن به‌طور خودکار پیدا نشد. اگر می‌دانید این دکمه فیزیکی چه کاری انجام می‌دهد، از فهرست زیر انتخاب کنید.',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.6),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _manualBtChoices.length,
              itemBuilder: (_, i) {
                final e = _manualBtChoices[i];
                return ListTile(
                  dense: true,
                  title: Text(e.remoteKey,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    'page=${e.page}  usage=0x${e.usage.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                    style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded, color: Color(0xFF4FC3F7)),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ],
      ),
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
