import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

enum BtConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

class BluetoothService extends ChangeNotifier {
  BluetoothService();

  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSub;

  BtConnectionStatus _status = BtConnectionStatus.disconnected;
  List<BluetoothDevice> _bonded = const [];
  BluetoothDevice? _device;
  String? _lastError;

  bool _automaticMode = false;
  int _speedDuty = 25000;

  BtConnectionStatus get status => _status;
  List<BluetoothDevice> get bonded => _bonded;
  BluetoothDevice? get device => _device;
  String? get lastError => _lastError;
  bool get isConnected => _status == BtConnectionStatus.connected;
  bool get automaticMode => _automaticMode;
  int get speedDuty => _speedDuty;

  Future<void> init() async {
    await ensureEnabled();
    await refreshBondedDevices();
  }

  Future<void> ensureEnabled() async {
    final enabled = await _bluetooth.isEnabled ?? false;
    if (enabled) return;
    await _bluetooth.requestEnable();
  }

  Future<void> refreshBondedDevices() async {
    try {
      _bonded = await _bluetooth.getBondedDevices();
      _lastError = null;
    } catch (e) {
      _lastError = 'Failed to read paired devices: $e';
    }
    notifyListeners();
  }

  Future<bool> connect(BluetoothDevice target) async {
    _status = BtConnectionStatus.connecting;
    _lastError = null;
    notifyListeners();

    try {
      await disconnect();
      final conn = await BluetoothConnection.toAddress(target.address);
      _connection = conn;
      _device = target;

      _inputSub = conn.input.listen(
        (_) {},
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );

      _status = BtConnectionStatus.connected;
      notifyListeners();
      return true;
    } catch (e) {
      _status = BtConnectionStatus.failed;
      _lastError = 'Connection failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;

    final conn = _connection;
    _connection = null;
    _status = BtConnectionStatus.disconnected;
    _device = null;
    notifyListeners();

    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
    }
  }

  Future<void> send(String command) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      _lastError = 'Not connected';
      notifyListeners();
      throw StateError('Not connected');
    }

    final payload = command.endsWith('\n') ? command : '$command\n';
    conn.output.add(Uint8List.fromList(utf8.encode(payload)));
    await conn.output.allSent;
  }

  Future<void> setSpeed(int value) async {
    final clamped = value.clamp(0, 65535);
    _speedDuty = clamped;
    notifyListeners();
    await send('E|$clamped');
  }

  Future<void> setAutomaticMode(bool automatic) async {
    _automaticMode = automatic;
    notifyListeners();
    await send(automatic ? 'AUTOMATIC' : 'MANUAL');
  }

  Future<void> sendManualCommand(String command) async {
    if (_automaticMode) {
      throw StateError('Manual command blocked while AUTOMATIC mode is active.');
    }
    await send(command);
  }

  Future<void> emergencyStop() async {
    _automaticMode = false;
    notifyListeners();
    await send('S');
  }

  void _handleDisconnect() {
    _connection = null;
    _inputSub = null;
    _status = BtConnectionStatus.disconnected;
    _device = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
