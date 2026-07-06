import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/shell/shell.dart';

void main() {
  runApp(const MoodyDashboardApp());
}

class MoodyDashboardApp extends StatelessWidget {
  const MoodyDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moody Blues Dashboard',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Shell(),
    );
  }
}