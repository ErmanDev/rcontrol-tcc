import 'package:flutter/material.dart';

/// Compact two-position loader-bucket control (hobby-servo Up / Down).
///
/// Not a rotary knob and not full-bleed: [Row.mainAxisSize] is min so the
/// chip is only as wide as the label + switch. Sit it in a centered row
/// under MANUAL/AUTOMATIC.
class LoaderBucketControl extends StatelessWidget {
  const LoaderBucketControl({
    super.key,
    required this.up,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  /// `true` = bucket up, `false` = bucket down (closed / safe).
  final bool up;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool compact;

  static const _accent = Color(0xFF2EE6A6);
  static const _panel = Color(0xFF1E2A33);
  static const _border = Color(0xFF3A4A56);

  @override
  Widget build(BuildContext context) {
    final labelColor = enabled ? Colors.white : Colors.white54;
    final downColor = !enabled
        ? Colors.white38
        : (!up ? _accent : Colors.white54);
    final upColor = !enabled
        ? Colors.white38
        : (up ? _accent : Colors.white54);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: up && enabled ? _accent.withValues(alpha: 0.55) : _border,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 2 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.agriculture,
              size: compact ? 18 : 22,
              color: enabled
                  ? (up ? _accent : Colors.white70)
                  : Colors.white38,
            ),
            SizedBox(width: compact ? 8 : 10),
            Text(
              'Loader Bucket',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 13 : 15,
                color: labelColor,
              ),
            ),
            SizedBox(width: compact ? 10 : 14),
            Text(
              'Down',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 12,
                letterSpacing: 0.4,
                color: downColor,
              ),
            ),
            Switch(
              value: up,
              onChanged: enabled ? onChanged : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeThumbColor: _accent,
              activeTrackColor: _accent.withValues(alpha: 0.45),
            ),
            Text(
              'Up',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 12,
                letterSpacing: 0.4,
                color: upColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
