import 'package:flutter_test/flutter_test.dart';
import 'package:remote_controller/services/bluetooth_service.dart';

void main() {
  BluetoothService fakeConnected() {
    final bt = BluetoothService.fake();
    bt.debugSetConnected();
    return bt;
  }

  test('setBlade sends BLADE|ON and BLADE|OFF', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.setBlade(true);
    expect(bt.bladeOn, isTrue);
    expect(bt.sentCommands, ['BLADE|ON']);

    await bt.setBlade(false);
    expect(bt.bladeOn, isFalse);
    expect(bt.sentCommands, ['BLADE|ON', 'BLADE|OFF']);
  });

  test('setBlade reverts and throws when disconnected', () async {
    final bt = BluetoothService.fake();
    addTearDown(bt.dispose);

    await expectLater(bt.setBlade(true), throwsA(isA<StateError>()));
    expect(bt.bladeOn, isFalse);
    expect(bt.sentCommands, isEmpty);
  });

  test('emergencyStop clears blade UI state and sends S then BLADE|OFF', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.setBlade(true);
    await bt.setAutomaticMode(true);
    expect(bt.bladeOn, isTrue);
    expect(bt.automaticMode, isTrue);

    await bt.emergencyStop();
    expect(bt.bladeOn, isFalse);
    expect(bt.automaticMode, isFalse);
    expect(bt.sentCommands, ['BLADE|ON', 'AUTOMATIC', 'S', 'BLADE|OFF']);
  });

  test('emergencyStop still sends BLADE|OFF when blade is already off', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.emergencyStop();
    expect(bt.bladeOn, isFalse);
    expect(bt.sentCommands, ['S', 'BLADE|OFF']);
  });
}
