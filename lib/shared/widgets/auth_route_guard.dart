import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/auth/screens/login_screen.dart';
import 'package:campus_square/features/auth/screens/splash_screen.dart';
import 'package:campus_square/features/dashboard/screens/dashboard_screen.dart';

class AuthRouteGuard extends StatelessWidget {
  const AuthRouteGuard({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<CampusSquareAuth>().status;

    switch (authState) {
      case ApplicationState.initializing:
        return const SplashScreen();
      case ApplicationState.authenticated:
        return const Dashboard();
      case ApplicationState.unauthenticated:
        return const LoginScreen();
    }
  }
}
