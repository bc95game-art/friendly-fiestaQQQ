import 'package:flutter/material.dart';
import '../models/remote_mode.dart';
import '../theme/colors.dart';
import 'size_picker_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.line, width: 1.5),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2B3A4A), Color(0xFF151A20)],
                  ),
                ),
                child: const Icon(Icons.tv_rounded, color: AppColors.text1, size: 36),
              ),
              const SizedBox(height: 24),
              const Text(
                'خوش آمدید',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.text1),
              ),
              const SizedBox(height: 8),
              const Text(
                'روش کنترل تلویزیون دوو خود را انتخاب کنید — مدل ۱۳۶۳',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.8, color: AppColors.text2, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 36),
              _ModeCard(
                title: 'کنترل با بلوتوث تلویزیون',
                subtitle: 'اتصال بی‌سیم — نیازمند Pair کردن بلوتوث تلویزیون از تنظیمات گوشی',
                icon: Icons.bluetooth_rounded,
                accent: AppColors.btAccent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SizePickerScreen(mode: RemoteMode.bluetooth)),
                ),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'کنترل با فرستنده مادون‌قرمز (IR)',
                subtitle: 'اگر گوشی شما فرستنده IR دارد',
                icon: Icons.settings_remote_rounded,
                accent: AppColors.irAccent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SizePickerScreen(mode: RemoteMode.ir)),
                ),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.success.withOpacity(0.4)),
                ),
                child: const Text.rich(
                  TextSpan(
                    text: 'استفاده ',
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                    children: [
                      TextSpan(text: 'رایگان', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                      TextSpan(text: ' برای تمام کاربران — بدون تبلیغات و بدون اشتراک'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title, subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: AppColors.line),
          gradient: LinearGradient(
            colors: [AppColors.panel, AppColors.panel2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text1)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
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
