import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DirectionButton extends StatelessWidget {
  const DirectionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.onReleased,
    this.active = false,
    this.enabled = true,
    this.size = 72,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback onReleased;
  final bool active;
  final bool enabled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? const Color(0xFF2EE6A6);
    final bg = active ? accent : const Color(0xFF1E2A33);
    final fg = active ? const Color(0xFF0B141A) : const Color(0xFFE8F1F5);

    return Listener(
      onPointerDown: enabled
          ? (_) {
              HapticFeedback.lightImpact();
              onPressed();
            }
          : null,
      onPointerUp: enabled ? (_) => onReleased() : null,
      onPointerCancel: enabled ? (_) => onReleased() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled ? bg : bg.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? accent : const Color(0xFF3A4A56),
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: enabled ? fg : fg.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
