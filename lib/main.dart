import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:campus_square/core/theme/app_theme.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/shared/widgets/auth_route_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  runApp(
    ChangeNotifierProvider(
      create: (_) => CampusSquareAuth(),
      child: const CampusSquareApp(),
    ),
  );
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
      debugShowCheckedModeBanner: false,
      home: const AuthRouteGuard(),
    );
  }
}
