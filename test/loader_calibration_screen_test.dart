import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remote_controller/screens/controller_screen.dart';
import 'package:remote_controller/screens/loader_calibration_screen.dart';
import 'package:remote_controller/services/bluetooth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(BluetoothService bt, {Widget? home}) {
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
        home: home ?? const ControllerScreen(),
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
        try {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        } catch (_) {
          if (!path.startsWith('test/goldens/')) continue;
          rethrow;
        }
      }
    });
  }

  testWidgets('linked slider sends LOADER|ANGLE and shows 180-n', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt, home: const LoaderCalibrationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Loader angle: 0°'), findsOneWidget);
    expect(find.textContaining('Right GP17: 180°'), findsWidgets);

    final slider = tester.widget<Slider>(find.byKey(const Key('loaderAngleSlider')));
    slider.onChanged!(60);
    await tester.pump();
    expect(find.text('Loader angle: 60°'), findsOneWidget);
    expect(find.textContaining('Right GP17: 120°'), findsWidgets);
    expect(loaderInvertedRightAngle(60), 120);
    expect(bt.sentCommands, isEmpty);

    await tester.pump(const Duration(milliseconds: 50));
    expect(bt.sentCommands, ['LOADER|ANGLE|60']);
  });

  testWidgets('independent sliders send raw LOADER|16 and LOADER|17', (
    tester,
  ) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt, home: const LoaderCalibrationScreen()));
    await tester.pumpAndSettle();

    tester.widget<Slider>(find.byKey(const Key('loaderGp16Slider'))).onChanged!(16);
    await tester.pump(const Duration(milliseconds: 50));
    tester.widget<Slider>(find.byKey(const Key('loaderGp17Slider'))).onChanged!(170);
    await tester.pump(const Duration(milliseconds: 50));

    expect(bt.sentCommands, ['LOADER|16|16', 'LOADER|17|170']);
    expect(find.text('Left GP16: 16°'), findsOneWidget);
    expect(find.text('Right GP17: 170°'), findsOneWidget);
  });

  testWidgets('calibration sliders disabled when disconnected', (tester) async {
    final bt = BluetoothService.fake();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt, home: const LoaderCalibrationScreen()));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Slider>(find.byKey(const Key('loaderAngleSlider'))).onChanged,
      isNull,
    );
    expect(
      tester.widget<Slider>(find.byKey(const Key('loaderGp16Slider'))).onChanged,
      isNull,
    );
    expect(
      tester.widget<Slider>(find.byKey(const Key('loaderGp17Slider'))).onChanged,
      isNull,
    );
  });

  testWidgets('compact landscape calibration does not overflow', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);

    for (final height in [360.0, 400.0]) {
      setLandscape(tester, width: 800, height: height);
      await tester.pumpWidget(app(bt, home: const LoaderCalibrationScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at h=$height');
      expect(find.byKey(const Key('loaderAngleSlider')), findsOneWidget);
    }
  });

  testWidgets('landscape screenshot of servo calibration', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester, width: 800, height: 400, dpr: 2);

    await tester.pumpWidget(app(bt, home: const LoaderCalibrationScreen()));
    await tester.pumpAndSettle();
    await saveLandscapeScreenshot(tester, 'loader_calibration.png');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/loader_calibration.png'),
    );
  });
}
