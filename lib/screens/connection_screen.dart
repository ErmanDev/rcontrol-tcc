import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_service.dart';
import 'controller_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bt = context.read<BluetoothService>();
    await bt.init();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    final bt = context.read<BluetoothService>();
    final ok = await bt.connect(device);
    if (!mounted) return;
    if (!ok) {
      final msg = bt.lastError ?? 'Connect failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ControllerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.watch<BluetoothService>();
    final paired = bt.bonded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Bluetooth'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bt.refreshBondedDevices(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2630),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2EE6A6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Pair your HC-05/HC-06 in Android Bluetooth settings first, then select it below.',
                    style: TextStyle(height: 1.35),
                  ),
                ),
                Expanded(
                  child: paired.isEmpty
                      ? const Center(
                          child: Text('No paired Bluetooth devices found'),
                        )
                      : ListView.separated(
                          itemCount: paired.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final device = paired[index];
                            final title = (device.name ?? '').trim().isEmpty
                                ? device.address
                                : '${device.name} (${device.address})';
                            return ListTile(
                              title: Text(title),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: bt.status == BtConnectionStatus.connecting
                                  ? null
                                  : () => _connect(device),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
