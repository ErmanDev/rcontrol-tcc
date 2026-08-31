import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/connection_screen.dart';
import 'services/bluetooth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const SmartMowerBluetoothApp());
}

class SmartMowerBluetoothApp extends StatelessWidget {
  const SmartMowerBluetoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BluetoothService(),
      child: MaterialApp(
        title: 'Smart Mower Bluetooth',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B141A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2EE6A6),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const ConnectionScreen(),
      ),
    );
  }
}
