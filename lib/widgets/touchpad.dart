import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// تاچ‌پد هوشمند — سبک EShare
///
/// رفتار:
///   • کشیدن انگشت  = حرکت نشانگر (سریع، مثل EShare)
///   • ضربه‌ی ساده  = کلیک / انتخاب گزینه
///
/// پارامترها:
///   [active]        آیا تاچ‌پد فعال است (کشیدن/ضربه ارسال می‌شود)
///   [accentColor]   رنگ حاشیه و نورافشانی (بلوتوث=آبی، وای‌فای=فیروزه)
///   [onMove]        کال‌بک حرکت: dx و dy به صورت عدد صحیح (پیکسل)
///   [onTap]         کال‌بک ضربه ساده (کلیک)
///   [onDragStart/End] برای قفل/آزاد اسکرول والد هنگام کشیدن
///   [hint]          متن راهنمای داخل پد (وقتی غیرفعال است)
class Touchpad extends StatefulWidget {
  const Touchpad({
    super.key,
    required this.active,
    required this.onMove,
    required this.onTap,
    this.accentColor = AppColors.btAccent,
    this.onDragStart,
    this.onDragEnd,
    this.hint,
    this.height = 180,
  });

  final bool active;
  final Color accentColor;
  final Future<void> Function(int dx, int dy) onMove;
  final Future<void> Function() onTap;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final String? hint;
  final double height;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad>
    with SingleTickerProviderStateMixin {
  // ── حساسیت — کالیبره‌شده برای رفتار مشابه EShare ──────────────────────
  // EShare ضریب بالاتری دارد تا با یک کشیدن کوچک نشانگر مسیر بیشتری برود.
  // مقدار ۳.۵ در تست‌های واقعی بیشترین شباهت را به EShare داشت.
  static const double _sensitivity = 3.5;

  // باقیمانده اعشاری برای جلوگیری از گردکردن خطادار در سرعت‌های پایین
  double _dxRem = 0, _dyRem = 0;

  // موقعیت انگشت برای اثر نورافشانی
  Offset? _glowPos;

  // تشخیص ضربه (tap) از کشیدن (drag)
  Offset? _panStartPos;
  bool _isDragging = false;
  static const double _tapThreshold = 8.0; // پیکسل

  // انیمیشن فشار (scale down هنگام ضربه)
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.active) return;
    _panStartPos = d.localPosition;
    _isDragging = false;
    _dxRem = 0;
    _dyRem = 0;
    setState(() => _glowPos = d.localPosition);
    _pressCtrl.forward();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.active) return;
    setState(() => _glowPos = d.localPosition);

    final dist = (d.localPosition - (_panStartPos ?? d.localPosition)).distance;
    if (!_isDragging && dist > _tapThreshold) {
      _isDragging = true;
      widget.onDragStart?.call();
    }

    if (!_isDragging) return;

    _dxRem += d.delta.dx * _sensitivity;
    _dyRem += d.delta.dy * _sensitivity;
    final dx = _dxRem.truncate();
    final dy = _dyRem.truncate();
    _dxRem -= dx;
    _dyRem -= dy;
    if (dx != 0 || dy != 0) {
      widget.onMove(dx, dy);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (!widget.active) return;
    final wasDragging = _isDragging;
    _isDragging = false;
    _panStartPos = null;
    _pressCtrl.reverse();
    setState(() => _glowPos = null);
    widget.onDragEnd?.call();

    // اگر کشیدن نبود (ضربه)، کلیک ارسال کن
    if (!wasDragging) {
      widget.onTap();
    }
  }

  void _onPanCancel() {
    _isDragging = false;
    _panStartPos = null;
    _pressCtrl.reverse();
    setState(() => _glowPos = null);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pressAnim,
      builder: (_, child) => Transform.scale(
        scale: _pressAnim.value,
        child: child,
      ),
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: widget.active
                  ? widget.accentColor
                  : AppColors.line,
              width: widget.active ? 1.8 : 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.active
                  ? [
                      widget.accentColor.withOpacity(0.06),
                      AppColors.bg2,
                    ]
                  : [AppColors.panel, AppColors.panel2],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── نورافشانی روی نقطه لمس ──────────────────────────────
              if (_glowPos != null && widget.active)
                Positioned(
                  left: _glowPos!.dx - 26,
                  top: _glowPos!.dy - 26,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.accentColor.withOpacity(0.45),
                          widget.accentColor.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── راهنما (وقتی غیرفعال) ───────────────────────────────
              if (!widget.active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.hint ??
                        'دکمه‌ی موس بالا را بزنید تا تاچ‌پد فعال شود',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text3,
                      height: 1.8,
                    ),
                  ),
                ),

              // ── راهنما (وقتی فعال) ──────────────────────────────────
              if (widget.active && _glowPos == null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 28,
                      color: widget.accentColor.withOpacity(0.35),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'بکشید = حرکت نشانگر · ضربه = انتخاب',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.accentColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
