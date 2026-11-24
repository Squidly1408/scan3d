import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // AR tracking + the camera preview are much simpler in a fixed orientation.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const Scan3dApp());
}

class Scan3dApp extends StatelessWidget {
  const Scan3dApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scan3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00BFA5),
      ),
      home: const HomeScreen(),
    );
  }
}
