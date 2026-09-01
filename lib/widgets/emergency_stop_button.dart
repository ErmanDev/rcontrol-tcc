import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmergencyStopButton extends StatelessWidget {
  const EmergencyStopButton({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: enabled
            ? () {
                HapticFeedback.heavyImpact();
                onPressed();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE53935),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE53935).withValues(alpha: 0.35),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('STOP'),
      ),
    );
  }
}
