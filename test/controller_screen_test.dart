import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remote_controller/screens/controller_screen.dart';
import 'package:remote_controller/services/bluetooth_service.dart';
import 'package:remote_controller/widgets/blade_switch.dart';
import 'package:remote_controller/widgets/emergency_stop_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(BluetoothService bt) {
    return ChangeNotifierProvider<BluetoothService>.value(
      value: bt,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: const Color(0xFF0B141A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2EE6A6),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const ControllerScreen(),
      ),
    );
  }

  void setLandscape(
    WidgetTester tester, {
    double width = 800,
    double height = 400,
    double dpr = 1,
  }) {
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> saveLandscapeScreenshot(
    WidgetTester tester,
    String filename,
  ) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byType(RepaintBoundary).first)
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData!.buffer.asUint8List();
      for (final path in [
        'test/goldens/$filename',
        '/opt/cursor/artifacts/$filename',
      ]) {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    });
  }

  testWidgets('blade switch is visible and disabled when disconnected', (
    tester,
  ) async {
    final bt = BluetoothService.fake();
    addTearDown(bt.dispose);
    setLandscape(tester, height: 360);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BladeSwitch), findsOneWidget);
    expect(find.text('Blade'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);

    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
    expect(sw.value, isFalse);
  });

  testWidgets('blade switch is enabled in manual and automatic when connected', (
    tester,
  ) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester, height: 400);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    var sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNotNull);

    await tester.tap(find.text('AUTOMATIC'));
    await tester.pumpAndSettle();
    expect(bt.automaticMode, isTrue);
    expect(find.byType(BladeSwitch), findsOneWidget);
    sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('toggling blade sends BLADE|ON and BLADE|OFF', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.bladeOn, isTrue);
    expect(bt.sentCommands, ['BLADE|ON']);
    expect(find.text('ON'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.bladeOn, isFalse);
    expect(bt.sentCommands, ['BLADE|ON', 'BLADE|OFF']);
    expect(find.text('OFF'), findsOneWidget);
  });

  testWidgets('emergency stop turns the blade switch off', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.bladeOn, isTrue);

    await tester.tap(find.widgetWithText(EmergencyStopButton, 'STOP'));
    await tester.pumpAndSettle();

    expect(bt.bladeOn, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('OFF'), findsOneWidget);
    expect(bt.sentCommands, ['BLADE|ON', 'S', 'BLADE|OFF']);
  });

  testWidgets('compact and taller landscape layouts do not overflow', (
    tester,
  ) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);

    for (final height in [360.0, 400.0, 720.0]) {
      setLandscape(tester, width: 800, height: height);
      await tester.pumpWidget(app(bt));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at h=$height');
      expect(find.byType(BladeSwitch), findsOneWidget);
      expect(find.byType(EmergencyStopButton), findsOneWidget);

      final blade = tester.getRect(find.byType(BladeSwitch));
      final stop = tester.getRect(find.byType(EmergencyStopButton));
      expect(blade.bottom <= stop.top + 0.5, isTrue,
          reason: 'blade switch must sit above e-stop at h=$height');
      expect(blade.height, lessThan(72),
          reason: 'blade row should stay compact at h=$height');
    }
  });

  testWidgets('landscape screenshots of blade off and on', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester, width: 800, height: 400, dpr: 2);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();
    await saveLandscapeScreenshot(tester, 'controller_blade_off.png');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/controller_blade_off.png'),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveLandscapeScreenshot(tester, 'controller_blade_on.png');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/controller_blade_on.png'),
    );
  });
}
