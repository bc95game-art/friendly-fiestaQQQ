import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/remote_mode.dart';
import '../services/ir_service.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import 'remote_screen.dart';

class SizePickerScreen extends StatelessWidget {
  const SizePickerScreen({super.key, required this.mode});
  final RemoteMode mode;

  Future<void> _showErrorDialog(BuildContext context, String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          side: const BorderSide(color: AppColors.line),
        ),
        title: const Text(
          'خطا',
          style: TextStyle(color: AppColors.text1, fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.text2, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('باشه',
                style: TextStyle(
                    color: AppColors.btAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, RemoteSize size) async {
    // ── وای‌فای: اتصال قبلاً برقرار شده، مستقیم به کنترل می‌رویم ────────
    if (mode.isWifi) {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => RemoteScreen(mode: mode, size: size)),
        );
      }
      return;
    }

    if (mode.isIr) {
      // ── بررسی وجود سخت‌افزار IR ─────────────────────────────────────────
      final hasIr = await IrService.instance.hasIrEmitter();
      if (!hasIr) {
        if (context.mounted) {
          await _showErrorDialog(
            context,
            'گوشی شما فرستنده مادون‌قرمز (IR) سخت‌افزاری ندارد',
          );
        }
        return;
      }
    } else {
      // ── درخواست مجوزهای بلوتوث ──────────────────────────────────────────
      final result = await PermissionsService.requestBluetoothPermissions();

      if (!result.granted) {
        if (!context.mounted) return;

        if (result.permanentlyDenied) {
          // مجوز از تنظیمات رد شده — باید کاربر را به تنظیمات اپ هدایت کنیم
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radiusMd),
                side: const BorderSide(color: AppColors.line),
              ),
              title: const Text(
                'مجوز بلوتوث لازم است',
                style: TextStyle(color: AppColors.text1, fontWeight: FontWeight.w700),
              ),
              content: const Text(
                'مجوز بلوتوث از تنظیمات رد شده است.\n'
                'برای فعال‌سازی دوباره، لطفاً به تنظیمات اپلیکیشن بروید و مجوز را اعطا کنید.',
                style: TextStyle(color: AppColors.text2, height: 1.7),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('انصراف',
                      style: TextStyle(color: AppColors.text3)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openAppSettings();
                  },
                  child: const Text('باز کردن تنظیمات',
                      style: TextStyle(
                          color: AppColors.btAccent,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );
        } else {
          // کاربر رد کرد (ولی permanently denied نیست — دفعه بعد می‌توان دوباره درخواست کرد)
          await _showErrorDialog(
            context,
            'برای اتصال بلوتوث، مجوز لازم است — دوباره امتحان کنید',
          );
        }
        return;
      }
    }

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RemoteScreen(mode: mode, size: size)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = mode.isBluetooth ? AppColors.btAccent : AppColors.irAccent;
    return Scaffold(
      appBar: AppBar(
          title: Text(mode.isBluetooth
              ? 'انتخاب کنترل — روش بلوتوثی'
              : mode.isWifi
                  ? 'انتخاب کنترل — روش وای‌فای'
                  : 'انتخاب کنترل — روش فرستنده')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _SizeCard(
              title: 'کنترل بزرگ',
              subtitle: 'تمام دکمه‌ها',
              accent: accent,
              onTap: () => _open(context, RemoteSize.large),
            ),
            const SizedBox(height: 16),
            _SizeCard(
              title: 'کنترل کوچک',
              subtitle: 'جمع‌وجور',
              accent: accent,
              onTap: () => _open(context, RemoteSize.small),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeCard extends StatelessWidget {
  const _SizeCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });
  final String title, subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: AppColors.line),
          color: AppColors.panel,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.smartphone_rounded, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text2)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
