import 'package:flutter/material.dart';
import '../theme/colors.dart';

enum RemoteButtonShape { round, square, pill, tiny }

class RemoteButton extends StatefulWidget {
  const RemoteButton({
    super.key,
    required this.child,
    required this.onTap,
    this.shape = RemoteButtonShape.round,
    this.accent,
    this.disabled = false,
    this.label,
  });

  final Widget child;
  final VoidCallback onTap;
  final RemoteButtonShape shape;
  final Color? accent;
  final bool disabled;
  final String? label;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  bool _pressed = false;

  BorderRadius get _radius {
    switch (widget.shape) {
      case RemoteButtonShape.round:
        return BorderRadius.circular(999);
      case RemoteButtonShape.square:
        return BorderRadius.circular(AppColors.radiusMd);
      case RemoteButtonShape.pill:
        return BorderRadius.circular(999);
      case RemoteButtonShape.tiny:
        return BorderRadius.circular(AppColors.radiusSm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.accent ?? AppColors.panel2;
    return Opacity(
      opacity: widget.disabled ? 0.35 : 1,
      child: GestureDetector(
        onTapDown: widget.disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: widget.disabled ? null : () => setState(() => _pressed = false),
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg, AppColors.panel3],
              ),
              borderRadius: _radius,
              border: Border.all(color: AppColors.line, width: 1),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(color: AppColors.text1, size: 20),
                  child: widget.child,
                ),
                if (widget.label != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.label!,
                    style: const TextStyle(fontSize: 10, color: AppColors.text2, fontWeight: FontWeight.w600),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
