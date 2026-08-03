import 'package:flutter/material.dart';

import 'features/home/home_page.dart';

void main() {
  runApp(const FinPilotApp());
}

class FinPilotApp extends StatelessWidget {
  const FinPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FinPilot Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF255A4A)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
      ),
      home: const HomePage(),
    );
  }
}
