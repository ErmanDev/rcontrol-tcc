import 'package:flutter/material.dart';

class SpeedSlider extends StatelessWidget {
  const SpeedSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Speed: $value',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF2EE6A6),
            inactiveTrackColor: const Color(0xFF3A4A56),
            thumbColor: const Color(0xFF2EE6A6),
            overlayColor: const Color(0xFF2EE6A6).withValues(alpha: 0.15),
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.clamp(0, 65535).toDouble(),
            min: 0,
            max: 65535,
            divisions: 100,
            onChanged: enabled ? (v) => onChanged(v.round()) : null,
            onChangeEnd: enabled ? (v) => onChangeEnd(v.round()) : null,
          ),
        ),
      ],
    );
  }
}
