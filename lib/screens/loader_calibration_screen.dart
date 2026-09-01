import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';

/// Landscape servo-calibration screen. Linked slider sends `LOADER|ANGLE|<n>`;
/// optional independent sliders send raw `LOADER|16|<n>` / `LOADER|17|<n>`.
class LoaderCalibrationScreen extends StatefulWidget {
  const LoaderCalibrationScreen({super.key});

  @override
  State<LoaderCalibrationScreen> createState() => _LoaderCalibrationScreenState();
}

class _LoaderCalibrationScreenState extends State<LoaderCalibrationScreen> {
  static const _debounce = Duration(milliseconds: 50);
  static const _accent = Color(0xFF2EE6A6);
  static const _panel = Color(0xFF1E2A33);
  static const _border = Color(0xFF3A4A56);

  int _linked = 0;
  int _gp16 = 0;
  int _gp17 = 180;
  Timer? _debounceTimer;
  Future<void> Function()? _pendingSend;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _safeSend(Future<void> Function() action) async {
    final bt = context.read<BluetoothService>();
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bt.lastError ?? '$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _queueSend(Future<void> Function() action) {
    _pendingSend = action;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _flushSend);
  }

  void _flushSend() {
    _debounceTimer?.cancel();
    final pending = _pendingSend;
    _pendingSend = null;
    if (pending == null) return;
    unawaited(_safeSend(pending));
  }

  void _onLinked(int n, {required bool flush}) {
    final bt = context.read<BluetoothService>();
    setState(() {
      _linked = n;
      _gp16 = n;
      _gp17 = loaderInvertedRightAngle(n);
    });
    final send = () => bt.setLoaderLinkedAngle(n);
    if (flush) {
      _pendingSend = send;
      _flushSend();
    } else {
      _queueSend(send);
    }
  }

  void _onGp16(int n, {required bool flush}) {
    final bt = context.read<BluetoothService>();
    setState(() {
      _gp16 = n;
      _linked = n;
    });
    final send = () => bt.setLoaderPin16(n);
    if (flush) {
      _pendingSend = send;
      _flushSend();
    } else {
      _queueSend(send);
    }
  }

  void _onGp17(int n, {required bool flush}) {
    final bt = context.read<BluetoothService>();
    setState(() {
      _gp17 = n;
    });
    final send = () => bt.setLoaderPin17(n);
    if (flush) {
      _pendingSend = send;
      _flushSend();
    } else {
      _queueSend(send);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.watch<BluetoothService>();
    final enabled = bt.isConnected;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Servo calibration'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 420;
            final gap = compact ? 6.0 : 10.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, compact ? 4 : 8, 16, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Loader angle: $_linked°',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: compact ? 14 : 16,
                                color: enabled ? Colors.white : Colors.white54,
                              ),
                            ),
                            SizedBox(height: compact ? 2 : 4),
                            Text(
                              'Linked invert ON  ·  Right GP17: ${_gp17}° (180−$_linked)',
                              style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                color: enabled
                                    ? _accent.withValues(alpha: 0.9)
                                    : Colors.white38,
                              ),
                            ),
                            _AngleSlider(
                              sliderKey: const Key('loaderAngleSlider'),
                              value: _linked,
                              enabled: enabled,
                              compact: compact,
                              onChanged: (n) => _onLinked(n, flush: false),
                              onChangeEnd: (n) => _onLinked(n, flush: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      flex: 2,
                      child: _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Independent (raw)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: compact ? 13 : 14,
                                color: enabled ? Colors.white : Colors.white54,
                              ),
                            ),
                            Text(
                              'Left GP16: $_gp16°',
                              style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                color: enabled ? Colors.white70 : Colors.white38,
                              ),
                            ),
                            _AngleSlider(
                              sliderKey: const Key('loaderGp16Slider'),
                              value: _gp16,
                              enabled: enabled,
                              compact: compact,
                              onChanged: (n) => _onGp16(n, flush: false),
                              onChangeEnd: (n) => _onGp16(n, flush: true),
                            ),
                            Text(
                              'Right GP17: $_gp17°',
                              style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                color: enabled ? Colors.white70 : Colors.white38,
                              ),
                            ),
                            _AngleSlider(
                              sliderKey: const Key('loaderGp17Slider'),
                              value: _gp17,
                              enabled: enabled,
                              compact: compact,
                              onChanged: (n) => _onGp17(n, flush: false),
                              onChangeEnd: (n) => _onGp17(n, flush: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _LoaderCalibrationScreenState._panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _LoaderCalibrationScreenState._border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: child,
      ),
    );
  }
}

class _AngleSlider extends StatelessWidget {
  const _AngleSlider({
    required this.sliderKey,
    required this.value,
    required this.enabled,
    required this.compact,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Key sliderKey;
  final int value;
  final bool enabled;
  final bool compact;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _LoaderCalibrationScreenState._accent,
        inactiveTrackColor: const Color(0xFF3A4A56),
        thumbColor: _LoaderCalibrationScreenState._accent,
        overlayColor: _LoaderCalibrationScreenState._accent.withValues(alpha: 0.15),
        trackHeight: compact ? 2.5 : 3,
        overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 10 : 14),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 6 : 8),
      ),
      child: Slider(
        key: sliderKey,
        value: value.clamp(0, 180).toDouble(),
        min: 0,
        max: 180,
        divisions: 180,
        label: '$value°',
        onChanged: enabled ? (v) => onChanged(v.round()) : null,
        onChangeEnd: enabled ? (v) => onChangeEnd(v.round()) : null,
      ),
    );
  }
}
