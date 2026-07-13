import 'package:flutter/material.dart';
import '../services/bt_hid_service.dart';
import '../theme/colors.dart';

/// تاچ‌پد موس واقعی — ویجت «کنترل‌شده» (Controlled): فعال/غیرفعال بودنش را
/// خودش تصمیم نمی‌گیرد، از دکمه‌ی مخصوص «موس» در کنترل کوچک می‌آید
/// (`active`). این باعث می‌شود فقط یک نقطه‌ی روشن/خاموش‌کردن مشخص وجود
/// داشته باشد — دقیقاً همان چیزی که طبق دکمه‌ی «فعال/غیرفعال کردن موس»
/// در رابط کاربری انتظار می‌رود.
///
/// ⚠️ رفتار قبلی (رفع‌شده): چون فعال‌سازی از خودِ پد (نگه‌داشتن انگشت)
/// می‌آمد، وقتی کاربر همزمان انگشت دیگری روی OK می‌گذاشت، ارسال پیوسته‌ی
/// گزارش‌های حرکت موس با ارسال دکمه‌ی OK رقابت می‌کرد. حالا فعال‌سازی
/// فقط از دکمه‌ی «موس» (بیرون از پد) می‌آید، پس نیازی به لمس هم‌زمان پد
/// نیست.
///
/// وقتی فعال است: کشیدن انگشت = حرکت نشانگر (با ضریب حساسیت بیشتر)،
/// و یک ضربه‌ی ساده (بدون حرکت) = کلیک موس روی همان نقطه‌ای که نشانگر
/// تلویزیون الان هست.
class Touchpad extends StatefulWidget {
  const Touchpad({
    super.key,
    required this.active,
    this.locked = false,
    this.onDragStart,
    this.onDragEnd,
  });
  final bool active;
  final bool locked;

  /// ⚠️ رفع باگ «کشیدن انگشت روی تاچ‌پد کل صفحه را اسکرول می‌کند»:
  /// چون این ویجت داخل یک ListView (در کنترل کوچک) قرار دارد، حرکت
  /// عمودی انگشت روی پد با اسکرولِ همان لیست در «آرنای ژست» (gesture
  /// arena) رقابت می‌کرد و گاهی لیست به‌جای نشانگر موس حرکت می‌کرد.
  /// این دو کال‌بک به والد اجازه می‌دهند وقتی کاربر روی پد می‌کشد،
  /// اسکرولِ لیست بیرونی را موقتاً قفل کند تا فقط نشانگر حرکت کند.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  // ضریب حساسیت نشانگر — رفع باگ «نشانگر خیلی کند/سنگین حرکت می‌کند».
  // قبلاً دقیقاً به‌اندازه‌ی px کشیده‌شده حرکت می‌کرد؛ حالا با این ضریب
  // بزرگ‌نمایی می‌شود تا با یک کشیدن کوچک، نشانگر مسیر بیشتری برود.
  static const double _sensitivity = 2.4;

  Offset? _glowPos;

  // باقیمانده‌ی اعشاری حرکت (تا با گرد کردن هر رویداد، دقت در سرعت‌های
  // کم از دست نرود)
  double _dxRemainder = 0;
  double _dyRemainder = 0;

  bool get _enabled => widget.active && !widget.locked;

  void _onUpdate(DragUpdateDetails d) {
    if (!_enabled) return;
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

  void _onTap() {
    if (!_enabled) return;
    BtHidService.instance.sendMouseClick();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onPanStart: (_) {
        if (_enabled) widget.onDragStart?.call();
      },
      onPanUpdate: _onUpdate,
      onPanEnd: (_) {
        setState(() => _glowPos = null);
        widget.onDragEnd?.call();
      },
      onPanCancel: () {
        setState(() => _glowPos = null);
        widget.onDragEnd?.call();
      },
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: widget.active ? AppColors.btAccent : AppColors.line,
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
              if (!widget.active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.locked
                        ? 'در حالت فرستنده، موس لمسی غیرفعال است'
                        : 'برای فعال‌کردن، دکمه‌ی موس بالا را بزنید',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3, height: 1.8),
                  ),
                ),
              if (widget.active)
                const Positioned(
                  bottom: 10,
                  child: Text(
                    'کشیدن = حرکت نشانگر · ضربه‌ی ساده = کلیک',
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
