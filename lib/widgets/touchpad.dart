import 'package:flutter/material.dart';
import '../services/bt_hid_service.dart';
import '../theme/colors.dart';

/// تاچ‌پد موس واقعی.
///
/// ⚠️ رفتار قبلی (رفع‌شده): فقط تا زمانی‌که انگشت روی صفحه «نگه‌داشته»
/// می‌شد موس فعال بود؛ همین باعث می‌شد وقتی کاربر همزمان انگشت دیگری را
/// روی دکمه‌ی OK می‌گذاشت (برای مثال حین کشیدن نشانگر)، ارسال پیوسته‌ی
/// گزارش‌های حرکت موس روی همان اتصال HID با ارسال دکمه‌ی OK رقابت می‌کرد
/// و گاهی OK دیر یا اصلاً به تلویزیون نمی‌رسید.
///
/// رفتار جدید: یک ضربه‌ی ساده حالت تاچ‌پد را «فعال»/«غیرفعال» می‌کند
/// (Toggle) — دیگر نیازی به نگه‌داشتن انگشت نیست. کاربر یک بار لمس می‌کند،
/// نشانگر را با کشیدن انگشت حرکت می‌دهد، و با یک ضربه‌ی دیگر آن را
/// غیرفعال می‌کند تا بدون تداخل سراغ بقیه‌ی دکمه‌ها (مثل OK) برود. کلیک
/// موس همچنان از دکمه‌ی مجزای 🖱 در کنترل کوچک ارسال می‌شود.
class Touchpad extends StatefulWidget {
  const Touchpad({super.key, this.locked = false});
  final bool locked;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  // ضریب حساسیت نشانگر — رفع باگ «نشانگر خیلی کند/سنگین حرکت می‌کند».
  // قبلاً دقیقاً به‌اندازه‌ی px کشیده‌شده حرکت می‌کرد؛ حالا با این ضریب
  // بزرگ‌نمایی می‌شود تا با یک کشیدن کوچک، نشانگر مسیر بیشتری برود.
  static const double _sensitivity = 2.4;

  Offset? _glowPos;
  bool _active = false;

  // باقیمانده‌ی اعشاری حرکت (تا با گرد کردن هر رویداد، دقت در سرعت‌های
  // کم از دست نرود)
  double _dxRemainder = 0;
  double _dyRemainder = 0;

  void _toggleActive() {
    if (widget.locked) return;
    setState(() {
      _active = !_active;
      if (!_active) _glowPos = null;
    });
  }

  void _onUpdate(DragUpdateDetails d) {
    if (widget.locked || !_active) return;
    setState(() => _glowPos = d.localPosition);

    _dxRemainder += d.delta.dx * _sensitivity;
    _dyRemainder += d.delta.dy * _sensitivity;
    final dx = _dxRemainder.truncate();
    final dy = _dyRemainder.truncate();
    _dxRemainder -= dx;
    _dyRemainder -= dy;
    if (dx != 0 || dy != 0) {
      BtHidService.instance.sendMouseMove(dx, dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleActive,
      onPanUpdate: _onUpdate,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _active ? AppColors.btAccent : AppColors.line,
            width: 1.5,
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF262F38), Color(0xFF14191F)],
          ),
        ),
        child: Opacity(
          opacity: widget.locked ? 0.4 : 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_glowPos != null)
                Positioned(
                  left: _glowPos!.dx - 14,
                  top: _glowPos!.dy - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [AppColors.btAccent, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (_active ? AppColors.btAccent : Colors.black).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    widget.locked ? 'غیرفعال' : (_active ? 'فعال' : 'خاموش'),
                    style: const TextStyle(fontSize: 11, color: AppColors.text1),
                  ),
                ),
              ),
              if (!_active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.locked
                        ? 'در حالت فرستنده، موس لمسی غیرفعال است'
                        : 'برای فعال‌کردن نشانگر، یک بار ضربه بزنید',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3, height: 1.8),
                  ),
                ),
              if (_active)
                const Positioned(
                  bottom: 10,
                  child: Text(
                    'برای غیرفعال‌کردن دوباره ضربه بزنید',
                    style: TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
