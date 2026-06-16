import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

void main() {
  runApp(const CampusSquareApp());
}

class CampusSquareApp extends StatelessWidget {
  const CampusSquareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Square',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(body: Center(child: Text("Campus Square"))),
    );
  }
}
