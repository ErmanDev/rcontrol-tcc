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
/// | `LOADER|UP`   | Request loader bucket up                     |
/// | `LOADER|DOWN` | Request loader bucket down (closed / safe)   |
/// | `LOADER|ANGLE|<n>` | Live linked pose 0–180 (GP17 = 180-n) |
/// | `LOADER|16|<n>` | Live raw left GP16 0–180                 |
/// | `LOADER|17|<n>` | Live raw right GP17 0–180 (no invert)    |
///
/// Pico firmware drives two positional hobby servos together:
/// GP16 (physical 21) and GP17 (physical 22). Rest/DOWN is 0°, UP is 60°.
/// `LOADER|UP` / `LOADER|DOWN` are handled in both MANUAL and AUTOMATIC.
/// Live cal lines apply immediately (no sweep). Emergency stop sends
/// `LOADER|DOWN` (safe) then `S`; firmware also lowers the bucket on `S`.
///
/// Linked invert: logical [leftAngle] on GP16, GP17 gets `180 - left`.
int loaderInvertedRightAngle(int leftAngle) {
  final left = leftAngle.clamp(0, 180);
  return 180 - left;
}

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
  bool _loaderUp = false;
  int _speedDuty = 25000;
  final List<String> _sentCommands = [];

  BtConnectionStatus get status => _status;
  List<BluetoothDevice> get bonded => _bonded;
  BluetoothDevice? get device => _device;
  String? get lastError => _lastError;
  bool get isConnected => _status == BtConnectionStatus.connected;
  bool get automaticMode => _automaticMode;
  bool get loaderUp => _loaderUp;
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
    _loaderUp = false;
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

  /// Sends `LOADER|UP` or `LOADER|DOWN`. Reverts [loaderUp] if the write fails.
  Future<void> setLoaderUp(bool up) async {
    final previous = _loaderUp;
    _loaderUp = up;
    notifyListeners();
    try {
      await send(up ? 'LOADER|UP' : 'LOADER|DOWN');
    } catch (_) {
      _loaderUp = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Live linked pose: `LOADER|ANGLE|<n>`. GP16=n, GP17=180-n on firmware.
  Future<void> setLoaderLinkedAngle(int angle) async {
    final clamped = angle.clamp(0, 180);
    await send('LOADER|ANGLE|$clamped');
  }

  /// Live raw left horn: `LOADER|16|<n>` (no invert).
  Future<void> setLoaderPin16(int angle) async {
    final clamped = angle.clamp(0, 180);
    await send('LOADER|16|$clamped');
  }

  /// Live raw right horn: `LOADER|17|<n>` (no invert — independent cal).
  Future<void> setLoaderPin17(int angle) async {
    final clamped = angle.clamp(0, 180);
    await send('LOADER|17|$clamped');
  }

  Future<void> emergencyStop() async {
    _automaticMode = false;
    _loaderUp = false;
    notifyListeners();
    Object? firstError;
    try {
      await send('LOADER|DOWN');
    } catch (e) {
      firstError = e;
    }
    try {
      await send('S');
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
      _loaderUp = false;
    }
    notifyListeners();
  }

  void _handleDisconnect() {
    _connection = null;
    _inputSub = null;
    _status = BtConnectionStatus.disconnected;
    _device = null;
    _loaderUp = false;
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
