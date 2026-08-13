import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/dashboard_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for a dedicated gateway device
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Dark status bar to match the dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const CruDocSmsGatewayApp());
}

class CruDocSmsGatewayApp extends StatelessWidget {
  const CruDocSmsGatewayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CruDoc SMS Gateway',
      theme: AppTheme.darkTheme,
      home: const DashboardScreen(),
    );
  }
}
