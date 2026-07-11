import 'package:flutter/material.dart';
import '../models/remote_mode.dart';
import '../services/ir_service.dart';
import '../services/permissions_service.dart';
import '../theme/colors.dart';
import 'remote_screen.dart';

class SizePickerScreen extends StatelessWidget {
  const SizePickerScreen({super.key, required this.mode});
  final RemoteMode mode;

  Future<void> _open(BuildContext context, RemoteSize size) async {
    if (mode.isIr) {
      final hasIr = await IrService.instance.hasIrEmitter();
      if (!hasIr) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('گوشی شما فرستنده مادون‌قرمز (IR) سخت‌افزاری ندارد')),
          );
        }
        return;
      }
    } else {
      final granted = await PermissionsService.requestBluetoothPermissions();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('برای اتصال بلوتوث، مجوز لازم است')),
          );
        }
        return;
      }
      if (size == RemoteSize.small) {
        await PermissionsService.requestMicrophonePermission();
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
      appBar: AppBar(title: Text('انتخاب حجم — ${mode.title}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _SizeCard(
              title: 'کنترل بزرگ',
              subtitle: mode.isBluetooth
                  ? 'تمام قابلیت‌ها — موس و ضبط صدا فعال'
                  : 'تمام قابلیت‌ها — موس و ضبط صدا غیرفعال',
              accent: accent,
              onTap: () => _open(context, RemoteSize.large),
            ),
            const SizedBox(height: 16),
            _SizeCard(
              title: 'کنترل کوچک',
              subtitle: mode.isBluetooth
                  ? 'جمع‌وجور — موس و ضبط صدا فعال'
                  : 'جمع‌وجور — موس و ضبط صدا غیرفعال',
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
  const _SizeCard({required this.title, required this.subtitle, required this.accent, required this.onTap});
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
              decoration: BoxDecoration(color: accent.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.smartphone_rounded, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text1)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
