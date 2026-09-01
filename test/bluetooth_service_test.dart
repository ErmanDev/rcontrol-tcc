import 'package:flutter_test/flutter_test.dart';
import 'package:remote_controller/services/bluetooth_service.dart';

void main() {
  BluetoothService fakeConnected() {
    final bt = BluetoothService.fake();
    bt.debugSetConnected();
    return bt;
  }

  test('setLoaderUp sends LOADER|UP and LOADER|DOWN', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.setLoaderUp(true);
    expect(bt.loaderUp, isTrue);
    expect(bt.sentCommands, ['LOADER|UP']);

    await bt.setLoaderUp(false);
    expect(bt.loaderUp, isFalse);
    expect(bt.sentCommands, ['LOADER|UP', 'LOADER|DOWN']);
  });

  test('setLoaderUp reverts and throws when disconnected', () async {
    final bt = BluetoothService.fake();
    addTearDown(bt.dispose);

    await expectLater(bt.setLoaderUp(true), throwsA(isA<StateError>()));
    expect(bt.loaderUp, isFalse);
    expect(bt.sentCommands, isEmpty);
  });

  test('emergencyStop lowers the loader then sends S', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.setLoaderUp(true);
    await bt.setAutomaticMode(true);
    expect(bt.loaderUp, isTrue);
    expect(bt.automaticMode, isTrue);

    await bt.emergencyStop();
    expect(bt.loaderUp, isFalse);
    expect(bt.automaticMode, isFalse);
    expect(bt.sentCommands, ['LOADER|UP', 'AUTOMATIC', 'LOADER|DOWN', 'S']);
  });

  test('emergencyStop still sends LOADER|DOWN then S when already down', () async {
    final bt = fakeConnected();
    addTearDown(bt.dispose);

    await bt.emergencyStop();
    expect(bt.loaderUp, isFalse);
    expect(bt.sentCommands, ['LOADER|DOWN', 'S']);
  });
}
