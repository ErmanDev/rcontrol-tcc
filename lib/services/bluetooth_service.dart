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

/// Bluetooth serial protocol (newline-terminated):
///
/// | Command       | Meaning                                      |
/// | ------------- | -------------------------------------------- |
/// | `F` / `B` / `L` / `R` | Manual drive (blocked in AUTOMATIC) |
/// | `S`           | Emergency stop (motors + leave AUTOMATIC)    |
/// | `E|<duty>`    | Motor PWM duty 0–65535                       |
/// | `AUTOMATIC` / `MANUAL` | Mode switch                    |
/// | `BLADE|ON`    | Request blade cutter on                      |
/// | `BLADE|OFF`   | Request blade cutter off                     |
///
/// Pico firmware currently has no blade GPIO; unknown lines are ignored
/// by `main_bluetooth.py`. The app still sends `BLADE|ON` / `BLADE|OFF`
/// so a future firmware hook-up does not require another UI change.
/// Emergency stop always follows `S` with `BLADE|OFF`.
class BluetoothService extends ChangeNotifier {
  BluetoothService() : _offline = false;

  /// Widget/unit tests: no radio, no `FlutterBluetoothSerial` plugin.
  @visibleForTesting
  BluetoothService.fake() : _offline = true;

  final bool _offline;
  FlutterBluetoothSerial? _plugin;

  FlutterBluetoothSerial get _bluetooth =>
      _plugin ??= FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSub;

  BtConnectionStatus _status = BtConnectionStatus.disconnected;
  List<BluetoothDevice> _bonded = const [];
  BluetoothDevice? _device;
  String? _lastError;

  bool _automaticMode = false;
  bool _bladeOn = false;
  int _speedDuty = 25000;
  final List<String> _sentCommands = [];

  BtConnectionStatus get status => _status;
  List<BluetoothDevice> get bonded => _bonded;
  BluetoothDevice? get device => _device;
  String? get lastError => _lastError;
  bool get isConnected => _status == BtConnectionStatus.connected;
  bool get automaticMode => _automaticMode;
  bool get bladeOn => _bladeOn;
  int get speedDuty => _speedDuty;

  /// Outgoing command lines without the trailing newline. Fake mode only
  /// (real sends still go over the serial socket).
  @visibleForTesting
  List<String> get sentCommands => List.unmodifiable(_sentCommands);

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
    _bladeOn = false;
    notifyListeners();

    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
    }
  }

  Future<void> send(String command) async {
    final line = command.endsWith('\n') ? command.substring(0, command.length - 1) : command;
    if (_offline) {
      if (_status != BtConnectionStatus.connected) {
        _lastError = 'Not connected';
        notifyListeners();
        throw StateError('Not connected');
      }
      _sentCommands.add(line);
      return;
    }

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

  /// Sends `BLADE|ON` or `BLADE|OFF`. Reverts [bladeOn] if the write fails.
  Future<void> setBlade(bool on) async {
    final previous = _bladeOn;
    _bladeOn = on;
    notifyListeners();
    try {
      await send(on ? 'BLADE|ON' : 'BLADE|OFF');
    } catch (_) {
      _bladeOn = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> emergencyStop() async {
    _automaticMode = false;
    _bladeOn = false;
    notifyListeners();
    Object? firstError;
    try {
      await send('S');
    } catch (e) {
      firstError = e;
    }
    try {
      await send('BLADE|OFF');
    } catch (e) {
      firstError ??= e;
    }
    if (firstError != null) throw firstError;
  }

  /// Marks the fake service connected so widget tests can render a live UI.
  @visibleForTesting
  void debugSetConnected({bool connected = true}) {
    _status = connected
        ? BtConnectionStatus.connected
        : BtConnectionStatus.disconnected;
    if (!connected) {
      _device = null;
      _bladeOn = false;
    }
    notifyListeners();
  }

  void _handleDisconnect() {
    _connection = null;
    _inputSub = null;
    _status = BtConnectionStatus.disconnected;
    _device = null;
    _bladeOn = false;
    notifyListeners();
  }

  @override
  void dispose() {
    final sub = _inputSub;
    _inputSub = null;
    final conn = _connection;
    _connection = null;
    unawaited(() async {
      await sub?.cancel();
      if (conn != null) {
        try {
          await conn.close();
        } catch (_) {}
      }
    }());
    super.dispose();
  }
}
