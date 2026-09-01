import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remote_controller/screens/controller_screen.dart';
import 'package:remote_controller/services/bluetooth_service.dart';
import 'package:remote_controller/widgets/emergency_stop_button.dart';
import 'package:remote_controller/widgets/loader_bucket_control.dart';

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
        try {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        } catch (_) {
          // Artifact mount can fail in some VMs; goldens path is required.
          if (!path.startsWith('test/goldens/')) continue;
          rethrow;
        }
      }
    });
  }

  testWidgets('loader bucket is visible and disabled when disconnected', (
    tester,
  ) async {
    final bt = BluetoothService.fake();
    addTearDown(bt.dispose);
    setLandscape(tester, height: 360);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LoaderBucketControl), findsOneWidget);
    expect(find.text('Loader Bucket'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Blade'), findsNothing);
    expect(find.byType(Slider), findsOneWidget); // speed only, not a rotary
    expect(find.byKey(const Key('loaderTestButton')), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('loaderTestButton'))).onTap,
      isNull,
    );

    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
    expect(sw.value, isFalse);
  });

  testWidgets('loader bucket is enabled in manual and automatic when connected', (
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
    expect(find.byType(LoaderBucketControl), findsOneWidget);
    sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('toggling loader sends LOADER|UP and LOADER|DOWN', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.loaderUp, isTrue);
    expect(bt.sentCommands, ['LOADER|UP']);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.loaderUp, isFalse);
    expect(bt.sentCommands, ['LOADER|UP', 'LOADER|DOWN']);
  });

  testWidgets('emergency stop lowers the loader bucket', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(bt.loaderUp, isTrue);

    await tester.tap(find.widgetWithText(EmergencyStopButton, 'STOP'));
    await tester.pumpAndSettle();

    expect(bt.loaderUp, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(bt.sentCommands, ['LOADER|UP', 'LOADER|DOWN', 'S']);
  });

  testWidgets('compact landscape: no overflow and control is not full width', (
    tester,
  ) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);

    for (final height in [360.0, 400.0, 720.0]) {
      setLandscape(tester, width: 800, height: height);
      await tester.pumpWidget(app(bt));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at h=$height');
      expect(find.byType(LoaderBucketControl), findsOneWidget);
      expect(find.byType(EmergencyStopButton), findsOneWidget);
      expect(find.text('Blade'), findsNothing);

      final loader = tester.getRect(find.byType(LoaderBucketControl));
      final bar = tester.getRect(find.byKey(const Key('loaderBucketBar')));
      final testBtn = tester.getRect(find.byKey(const Key('loaderTestButton')));
      final stop = tester.getRect(find.byType(EmergencyStopButton));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(loader.bottom <= stop.top + 0.5, isTrue,
          reason: 'loader control must sit above e-stop at h=$height');
      expect(loader.height, lessThan(72),
          reason: 'loader row should stay compact at h=$height');
      expect(loader.width, lessThan(screen.width * 0.72),
          reason: 'loader chip must not stretch full width at h=$height');
      expect(testBtn.width, lessThan(120),
          reason: 'Test button must stay compact, not full width, at h=$height');
      expect(bar.width, lessThan(screen.width * 0.85),
          reason: 'loader+Test row must not stretch full width at h=$height');
      expect(
        (bar.left - screen.left - (screen.right - bar.right)).abs(),
        lessThan(24),
        reason: 'loader+Test row should be centered at h=$height',
      );
    }
  });

  testWidgets('landscape screenshots of loader down and up', (tester) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester, width: 800, height: 400, dpr: 2);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();
    await saveLandscapeScreenshot(tester, 'loader_bucket_down.png');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/loader_bucket_down.png'),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveLandscapeScreenshot(tester, 'loader_bucket_up.png');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/loader_bucket_up.png'),
    );
  });

  testWidgets('Test button pushes servo calibration and back returns', (
    tester,
  ) async {
    final bt = BluetoothService.fake()..debugSetConnected();
    addTearDown(bt.dispose);
    setLandscape(tester, height: 400);

    await tester.pumpWidget(app(bt));
    await tester.pumpAndSettle();

    expect(find.byType(LoaderBucketControl), findsOneWidget);
    await tester.tap(find.byKey(const Key('loaderTestButton')));
    await tester.pumpAndSettle();

    expect(find.text('Servo calibration'), findsOneWidget);
    expect(find.textContaining('Loader angle:'), findsOneWidget);
    expect(find.byKey(const Key('loaderAngleSlider')), findsOneWidget);
    expect(find.byKey(const Key('loaderGp16Slider')), findsOneWidget);
    expect(find.byKey(const Key('loaderGp17Slider')), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Servo calibration'), findsNothing);
    expect(find.byType(LoaderBucketControl), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });
}
