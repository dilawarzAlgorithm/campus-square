import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/auth/screens/login_screen.dart';
import 'package:campus_square/features/auth/screens/splash_screen.dart';
import 'package:campus_square/features/auth/screens/force_password_change_screen.dart';
import 'package:campus_square/features/dashboard/screens/dashboard_screen.dart';
import 'package:campus_square/features/admin/screens/admin_dashboard.dart';
import 'package:campus_square/features/community/screens/community_head_dashboard.dart';

class AuthRouteGuard extends StatelessWidget {
  const AuthRouteGuard({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<CampusSquareAuth>();
    final authState = authProvider.status;
    final user = authProvider.user;

    switch (authState) {
      case ApplicationState.initializing:
        return const SplashScreen();
      case ApplicationState.unauthenticated:
        return const LoginScreen();
      case ApplicationState.authenticated:
        if (user?['requires_password_change'] == true) {
          return const ForcePasswordChangeScreen();
        }

        final role = user?['role'] ?? 'STUDENT';

        switch (role) {
          case 'ADMIN':
            return const AdminDashboardScreen();
          case 'COMMUNITY_HEAD':
            return const CommunityHeadDashboardScreen();
          case 'CAPTAIN':
          case 'STUDENT':
          default:
            return const Dashboard();
        }
    }
  }
}
