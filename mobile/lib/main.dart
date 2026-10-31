import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/finpilot_theme.dart';
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
      theme: finPilotTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
        Locale('fr'),
      ],
      home: const HomePage(),
    );
  }
}
