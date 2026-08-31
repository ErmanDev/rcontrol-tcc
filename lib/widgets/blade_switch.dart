import 'package:flutter/material.dart';

/// Compact labeled Material [Switch] for the mower blade.
///
/// Sized for landscape phones: shrink-wrapped tap target, optional [compact]
/// density, and a single horizontal row so it can sit under MANUAL/AUTOMATIC
/// without stealing the D-pad / e-stop column.
class BladeSwitch extends StatelessWidget {
  const BladeSwitch({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool compact;

  static const _accent = Color(0xFF2EE6A6);
  static const _panel = Color(0xFF1E2A33);
  static const _border = Color(0xFF3A4A56);

  @override
  Widget build(BuildContext context) {
    final labelColor = enabled ? Colors.white : Colors.white54;
    final statusColor = !enabled
        ? Colors.white38
        : (value ? _accent : Colors.white54);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value && enabled
              ? _accent.withValues(alpha: 0.55)
              : _border,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 2 : 6,
        ),
        child: Row(
          children: [
            Icon(
              Icons.grass,
              size: compact ? 18 : 22,
              color: enabled
                  ? (value ? _accent : Colors.white70)
                  : Colors.white38,
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Text(
                'Blade',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 15,
                  color: labelColor,
                ),
              ),
            ),
            Text(
              value ? 'ON' : 'OFF',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 12,
                letterSpacing: 0.6,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 4),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeThumbColor: _accent,
              activeTrackColor: _accent.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
