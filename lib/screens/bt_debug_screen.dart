import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/remote_input_handler.dart';
import '../theme/colors.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  BtDebugScreen — صفحه شناسایی دکمه‌های ریموت فیزیکی بلوتوثی
// ══════════════════════════════════════════════════════════════════════════════
//
//  چطور استفاده کنیم:
//   ۱. ریموت فیزیکی دوو را به همین گوشی Pair کنید
//   ۲. این صفحه را باز کنید (آیکون 🪲 در AppBar کنترل بلوتوثی)
//   ۳. هر دکمه روی ریموت را فشار دهید
//   ۴. logicalId و physicalId نمایش داده می‌شود
//   ۵. کد مقدار logicalId دکمه‌های ناشناخته را در customKeyMap بنویسید
// ══════════════════════════════════════════════════════════════════════════════

class BtDebugScreen extends StatefulWidget {
  const BtDebugScreen({super.key});

  @override
  State<BtDebugScreen> createState() => _BtDebugScreenState();
}

class _BtDebugScreenState extends State<BtDebugScreen> {
  final List<_KeyLogEntry> _logs = [];
  bool _showOnlyDown = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  bool _onHardwareKey(KeyEvent event) {
    // فیلتر KeyRepeat برای جلوگیری از flood
    if (event is KeyRepeatEvent) return false;
    if (_showOnlyDown && event is! KeyDownEvent) return false;

    final entry = _KeyLogEntry(
      type: event is KeyDownEvent ? 'DOWN' : 'UP',
      logicalName: event.logicalKey.debugName ?? '(بدون نام)',
      logicalId: '0x${event.logicalKey.keyId.toRadixString(16).padLeft(8, '0').toUpperCase()}',
      physicalName: event.physicalKey.debugName ?? '(بدون نام)',
      usbHid: '0x${event.physicalKey.usbHidUsage.toRadixString(16).padLeft(8, '0').toUpperCase()}',
      resolvedAction: RemoteInputHandler.resolve(event),
      time: TimeOfDay.now(),
    );

    if (mounted) {
      setState(() {
        _logs.insert(0, entry);
        // حداکثر ۵۰ رویداد نگه داری کن
        if (_logs.length > 50) _logs.removeLast();
      });
    }
    // false = اجازه می‌دهیم رویداد به بقیه framework هم برسد
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug — دکمه‌های ریموت BT'),
        actions: [
          // toggle نمایش UP هم
          IconButton(
            icon: Icon(
              _showOnlyDown ? Icons.arrow_downward_rounded : Icons.swap_vert_rounded,
              color: _showOnlyDown ? AppColors.btAccent : AppColors.text2,
            ),
            tooltip: _showOnlyDown ? 'فقط DOWN — ضربه برای تغییر' : 'DOWN و UP — ضربه برای تغییر',
            onPressed: () => setState(() {
              _showOnlyDown = !_showOnlyDown;
              _logs.clear();
            }),
          ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'پاک کردن همه',
              onPressed: () => setState(() => _logs.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          _InfoBanner(),
          const Divider(height: 1, color: AppColors.line),
          Expanded(
            child: _logs.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => _LogCard(entry: _logs[i], index: i),
                  ),
          ),
          _QuickReference(),
        ],
      ),
    );
  }
}

// ── اطلاعات راهنما ────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.btAccentDim,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: AppColors.btAccent.withOpacity(0.35)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bluetooth_searching_rounded, color: AppColors.btAccent, size: 15),
            SizedBox(width: 6),
            Text(
              'راهنمای استفاده',
              style: TextStyle(color: AppColors.btAccent, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ]),
          SizedBox(height: 8),
          Text(
            '۱. ریموت فیزیکی دوو را از تنظیمات گوشی به همین گوشی Pair کنید\n'
            '۲. هر دکمه روی ریموت را فشار دهید — اطلاعات آن اینجا نمایش داده می‌شود\n'
            '۳. logicalId دکمه‌های "Unidentified" را کپی کنید\n'
            '۴. آن کد را در فایل remote_input_handler.dart → customKeyMap اضافه کنید',
            style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }
}

// ── حالت خالی ─────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, size: 56, color: AppColors.text4),
          SizedBox(height: 14),
          Text(
            'منتظر فشردن دکمه روی ریموت...',
            style: TextStyle(color: AppColors.text3, fontSize: 14),
          ),
          SizedBox(height: 6),
          Text(
            'مطمئن شوید ریموت Pair است',
            style: TextStyle(color: AppColors.text4, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── کارت هر رویداد ────────────────────────────────────────────────────────────
class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry, required this.index});
  final _KeyLogEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isDown = entry.type == 'DOWN';
    final isIdentified = entry.resolvedAction != null;
    final isUnknown = entry.logicalName.contains('Unidentified') ||
        entry.logicalName == '(بدون نام)' ||
        entry.logicalId.endsWith('00000000');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        border: Border.all(
          color: isUnknown
              ? AppColors.irAccent.withOpacity(0.5)
              : isIdentified
                  ? AppColors.btAccent.withOpacity(0.4)
                  : AppColors.line,
          width: isUnknown ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── سطر اول: نوع رویداد + اکشن + زمان ─────────────────────────
          Row(
            children: [
              _Badge(
                label: entry.type,
                color: isDown ? AppColors.success : AppColors.text3,
              ),
              const SizedBox(width: 6),
              if (isIdentified) ...[
                _Badge(
                  label: '→ ${entry.resolvedAction!.name}',
                  color: AppColors.btAccent,
                ),
                const SizedBox(width: 6),
              ],
              if (isUnknown)
                _Badge(label: '⚠ ناشناخته — کد را یادداشت کنید', color: AppColors.irAccent),
              const Spacer(),
              Text(
                '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: AppColors.text4, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── logicalKey ─────────────────────────────────────────────────
          _DataRow(
            label: 'logicalKey',
            value: entry.logicalName,
            code: entry.logicalId,
            codeColor: isUnknown ? AppColors.irAccent : AppColors.btAccentLight,
            copyable: true,
          ),
          const SizedBox(height: 5),

          // ── physicalKey ────────────────────────────────────────────────
          _DataRow(
            label: 'physicalKey',
            value: entry.physicalName,
            code: entry.usbHid,
            codeColor: AppColors.text2,
            copyable: false,
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    required this.code,
    required this.codeColor,
    required this.copyable,
  });

  final String label, value, code;
  final Color codeColor;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 11)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: copyable
              ? () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$code کپی شد'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: codeColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  code,
                  style: TextStyle(color: codeColor, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                if (copyable) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.copy_rounded, size: 11, color: codeColor.withOpacity(0.7)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ── جدول سریع دکمه‌های شناخته‌شده ────────────────────────────────────────────
class _QuickReference extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const known = [
      ('ArrowLeft', '0x00100000302', 'channelDown'),
      ('ArrowRight', '0x00100000303', 'channelUp'),
      ('MediaPlayPause', '0x00200000208', 'togglePlayPause'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
        color: AppColors.bg1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'دکمه‌های شناخته‌شده:',
            style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...known.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(e.$1, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                    const SizedBox(width: 4),
                    Text(e.$2, style: const TextStyle(color: AppColors.text4, fontSize: 10)),
                    const Spacer(),
                    Text(e.$3, style: const TextStyle(color: AppColors.btAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── مدل داده ──────────────────────────────────────────────────────────────────
class _KeyLogEntry {
  final String type;
  final String logicalName;
  final String logicalId;
  final String physicalName;
  final String usbHid;
  final RemoteAction? resolvedAction;
  final TimeOfDay time;

  const _KeyLogEntry({
    required this.type,
    required this.logicalName,
    required this.logicalId,
    required this.physicalName,
    required this.usbHid,
    required this.resolvedAction,
    required this.time,
  });
}
