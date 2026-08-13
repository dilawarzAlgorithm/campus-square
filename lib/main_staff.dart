import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:campus_square/core/theme/theme_provider.dart';
import 'package:campus_square/core/services/notification_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/auth/screens/staff_login_screen.dart';
import 'package:campus_square/features/auth/screens/splash_screen.dart';
import 'package:campus_square/features/auth/screens/force_password_change_screen.dart';
import 'package:campus_square/features/admin/screens/admin_dashboard.dart';
import 'package:campus_square/features/community/screens/community_head_dashboard.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CampusSquareAuth()),
        ChangeNotifierProxyProvider<CampusSquareAuth, NotificationProvider>(
          create: (_) => NotificationProvider()..initialize(),
          update: (_, auth, notif) {
            notif?.setUserId(auth.user?['id']);
            return notif!;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..initialize()),
      ],
      child: const CampusSquareStaffApp(),
    ),
  );
}

class CampusSquareStaffApp extends StatelessWidget {
  const CampusSquareStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Campus Square Admin',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: const StaffRouteGuard(),
    );
  }
}

class StaffRouteGuard extends StatelessWidget {
  const StaffRouteGuard({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<CampusSquareAuth>();
    final authState = authProvider.status;
    final user = authProvider.user;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _getScreenForState(context, authState, user),
    );
  }

  Widget _getScreenForState(
    BuildContext context,
    ApplicationState state,
    Map<String, dynamic>? user,
  ) {
    switch (state) {
      case ApplicationState.initializing:
        return const SplashScreen();
      case ApplicationState.unauthenticated:
        return const StaffLoginScreen(isStandaloneApp: true);
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
          default:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Students must use the Student App.'),
                  backgroundColor: Colors.red,
                ),
              );
              context.read<CampusSquareAuth>().logoutForcefully();
            });
            return const StaffLoginScreen(isStandaloneApp: true);
        }
    }
  }
}
