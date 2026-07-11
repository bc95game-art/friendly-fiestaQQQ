import 'package:flutter/material.dart';
import '../services/bt_hid_service.dart';
import '../theme/colors.dart';

/// تاچ‌پد موس واقعی: طبق رفتار کنترل اصلی دوو -
/// وقتی انگشت روی صفحه فشار داده می‌شود موس «فعال» و داده حرکت ارسال می‌شود؛
/// به‌محض برداشتن انگشت، موس «غیرفعال» می‌شود (بدون نیاز به دکمه‌ی جدا).
class Touchpad extends StatefulWidget {
  const Touchpad({super.key, this.locked = false});
  final bool locked;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  Offset? _glowPos;
  bool _active = false;

  void _onStart(DragStartDetails d) {
    if (widget.locked) return;
    setState(() {
      _active = true;
      _glowPos = d.localPosition;
    });
  }

  void _onUpdate(DragUpdateDetails d) {
    if (widget.locked || !_active) return;
    setState(() => _glowPos = d.localPosition);
    final dx = d.delta.dx.round();
    final dy = d.delta.dy.round();
    if (dx != 0 || dy != 0) {
      BtHidService.instance.sendMouseMove(dx, dy);
    }
  }

  void _onEnd(DragEndDetails d) {
    setState(() {
      _active = false;
      _glowPos = null;
    });
  }

  void _onTap() {
    if (widget.locked) return;
    BtHidService.instance.sendMouseClick();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onStart,
      onPanUpdate: _onUpdate,
      onPanEnd: _onEnd,
      onTap: _onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line, width: 1.5),
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
              if (widget.locked)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text('غیرفعال', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ),
                ),
              if (!_active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.locked
                        ? 'در حالت فرستنده، موس لمسی غیرفعال است'
                        : 'انگشت را روی این صفحه نگه‌دارید و بکشید',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.text3, height: 1.8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
