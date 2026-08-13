import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:campus_square/core/theme/theme_provider.dart';
import 'package:campus_square/core/services/notification_service.dart';
import 'package:campus_square/core/services/local_notification_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/timetable/screens/alarm_screen.dart';
import 'package:campus_square/features/auth/screens/login_screen.dart';
import 'package:campus_square/features/auth/screens/splash_screen.dart';
import 'package:campus_square/features/dashboard/screens/dashboard_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  final NotificationAppLaunchDetails? launchDetails = await plugin
      .getNotificationAppLaunchDetails();

  bool isAlarmLaunch = false;
  if (launchDetails?.didNotificationLaunchApp ?? false) {
    if (launchDetails?.notificationResponse?.payload == 'alarm_screen') {
      isAlarmLaunch = true;
    }
  }

  try {
    await LocalNotificationService.initialize(navigatorKey);
  } catch (e) {
    debugPrint("Local Notifications failed to initialize: $e");
  }

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
      child: CampusSquareStudentApp(isAlarmLaunch: isAlarmLaunch),
    ),
  );
}

class CampusSquareStudentApp extends StatelessWidget {
  const CampusSquareStudentApp({super.key, required this.isAlarmLaunch});
  final bool isAlarmLaunch;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Campus Square',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: isAlarmLaunch ? const AlarmScreen() : const StudentRouteGuard(),
    );
  }
}

class StudentRouteGuard extends StatelessWidget {
  const StudentRouteGuard({super.key});

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
        return const LoginScreen();
      case ApplicationState.authenticated:
        final role = user?['role'] ?? 'STUDENT';
        if (role == 'ADMIN' || role == 'COMMUNITY_HEAD') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Staff must use the Staff App.'),
                backgroundColor: Colors.red,
              ),
            );
            context.read<CampusSquareAuth>().logoutForcefully();
          });
          return const LoginScreen();
        }

        return const Dashboard();
    }
  }
}
