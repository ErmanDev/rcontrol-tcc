import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import '../widgets/direction_button.dart';
import '../widgets/loader_bucket_control.dart';
import '../widgets/emergency_stop_button.dart';
import '../widgets/speed_slider.dart';
import 'connection_screen.dart';
import 'loader_calibration_screen.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  static const _repeatInterval = Duration(milliseconds: 120);

  Timer? _repeatTimer;
  String? _held;
  int? _localSpeed;

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

  Future<void> _startHold(String command) async {
    final bt = context.read<BluetoothService>();
    if (!bt.isConnected || bt.automaticMode) return;

    await _stopHold(sendStop: false);
    _held = command;
    await _safeSend(() => bt.sendManualCommand(command));
    _repeatTimer = Timer.periodic(_repeatInterval, (_) {
      final current = _held;
      if (current == null) return;
      _safeSend(() => bt.sendManualCommand(current));
    });
    if (mounted) setState(() {});
  }

  Future<void> _stopHold({bool sendStop = true}) async {
    final bt = context.read<BluetoothService>();
    final wasHolding = _held != null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _held = null;
    if (mounted) setState(() {});
    if (sendStop && wasHolding) {
      await _safeSend(() => bt.emergencyStop());
    }
  }

  Future<void> _disconnect() async {
    final bt = context.read<BluetoothService>();
    await _stopHold(sendStop: false);
    await bt.disconnect();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.watch<BluetoothService>();
    final speed = _localSpeed ?? bt.speedDuty;
    final manualEnabled = bt.isConnected && !bt.automaticMode;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          bt.device?.name == null
              ? 'Bluetooth Controller'
              : 'Connected: ${bt.device!.name}',
        ),
        actions: [
          TextButton(
            onPressed: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 620;
            final buttonSize = compact ? 60.0 : 74.0;
            final padGap = compact ? 8.0 : 12.0;
            final sectionGap = compact ? 8.0 : 12.0;
            final centerPanelWidth = compact ? 320.0 : 380.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bt.automaticMode
                                ? 'AUTOMATIC: car handles obstacle detection + boustrophedon turns'
                                : 'MANUAL: direct low-latency control',
                            style: TextStyle(
                              color: bt.automaticMode
                                  ? Colors.orangeAccent
                                  : const Color(0xFF2EE6A6),
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 13 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: bt.isConnected
                                ? () => _safeSend(() => bt.setAutomaticMode(false))
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: bt.automaticMode
                                  ? const Color(0xFF1E2A33)
                                  : const Color(0xFF2EE6A6),
                              foregroundColor: bt.automaticMode
                                  ? Colors.white
                                  : const Color(0xFF0B141A),
                            ),
                            child: const Text('MANUAL'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: bt.isConnected
                                ? () async {
                                    await _stopHold(sendStop: false);
                                    await _safeSend(
                                      () => bt.setAutomaticMode(true),
                                    );
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: bt.automaticMode
                                  ? const Color(0xFF2EE6A6)
                                  : const Color(0xFF1E2A33),
                              foregroundColor: bt.automaticMode
                                  ? const Color(0xFF0B141A)
                                  : Colors.white,
                            ),
                            child: const Text('AUTOMATIC'),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    Align(
                      alignment: Alignment.center,
                      child: Row(
                        key: const Key('loaderBucketBar'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LoaderBucketControl(
                            up: bt.loaderUp,
                            enabled: bt.isConnected,
                            compact: compact,
                            onChanged: (up) =>
                                _safeSend(() => bt.setLoaderUp(up)),
                          ),
                          SizedBox(width: compact ? 8 : 10),
                          _LoaderTestButton(
                            enabled: bt.isConnected,
                            compact: compact,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const LoaderCalibrationScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: sectionGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _VerticalControl(
                            enabled: manualEnabled,
                            topIcon: Icons.keyboard_arrow_up_rounded,
                            bottomIcon: Icons.keyboard_arrow_down_rounded,
                            topActive: _held == 'F',
                            bottomActive: _held == 'B',
                            topCommand: 'F',
                            bottomCommand: 'B',
                            size: buttonSize,
                            gap: padGap,
                            onStart: _startHold,
                            onStop: _stopHold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: centerPanelWidth,
                          child: Column(
                            children: [
                              SpeedSlider(
                                value: speed,
                                enabled: bt.isConnected,
                                onChanged: (value) =>
                                    setState(() => _localSpeed = value),
                                onChangeEnd: (value) async {
                                  setState(() => _localSpeed = value);
                                  await _safeSend(() => bt.setSpeed(value));
                                },
                              ),
                              const SizedBox(height: 10),
                              EmergencyStopButton(
                                enabled: bt.isConnected,
                                onPressed: () =>
                                    _safeSend(() => bt.emergencyStop()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _VerticalControl(
                            enabled: manualEnabled,
                            topIcon: Icons.keyboard_arrow_left_rounded,
                            bottomIcon: Icons.keyboard_arrow_right_rounded,
                            topActive: _held == 'L',
                            bottomActive: _held == 'R',
                            topCommand: 'L',
                            bottomCommand: 'R',
                            size: buttonSize,
                            gap: padGap,
                            onStart: _startHold,
                            onStop: _stopHold,
                          ),
                        ),
                      ],
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

class _LoaderTestButton extends StatelessWidget {
  const _LoaderTestButton({
    required this.enabled,
    required this.compact,
    required this.onPressed,
  });

  final bool enabled;
  final bool compact;
  final VoidCallback onPressed;

  static const _accent = Color(0xFF2EE6A6);
  static const _panel = Color(0xFF1E2A33);
  static const _border = Color(0xFF3A4A56);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 32 : 40,
      child: FilledButton(
        key: const Key('loaderTestButton'),
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: _panel,
          foregroundColor: enabled ? _accent : Colors.white38,
          disabledBackgroundColor: _panel,
          disabledForegroundColor: Colors.white38,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          minimumSize: Size(0, compact ? 32 : 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 13 : 14,
          ),
        ),
        child: const Text('Test'),
      ),
    );
  }
}

class _VerticalControl extends StatelessWidget {
  const _VerticalControl({
    required this.enabled,
    required this.topIcon,
    required this.bottomIcon,
    required this.topActive,
    required this.bottomActive,
    required this.topCommand,
    required this.bottomCommand,
    required this.onStart,
    required this.onStop,
    required this.size,
    required this.gap,
  });

  final bool enabled;
  final IconData topIcon;
  final IconData bottomIcon;
  final bool topActive;
  final bool bottomActive;
  final String topCommand;
  final String bottomCommand;
  final ValueChanged<String> onStart;
  final Future<void> Function() onStop;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DirectionButton(
          icon: topIcon,
          size: size,
          enabled: enabled,
          active: topActive,
          onPressed: () => onStart(topCommand),
          onReleased: () => unawaited(onStop()),
        ),
        SizedBox(height: gap),
        DirectionButton(
          icon: bottomIcon,
          size: size,
          enabled: enabled,
          active: bottomActive,
          onPressed: () => onStart(bottomCommand),
          onReleased: () => unawaited(onStop()),
        ),
      ],
    );
  }
}
