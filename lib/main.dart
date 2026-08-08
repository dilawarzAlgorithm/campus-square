import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:campus_square/core/theme/app_theme.dart';
import 'package:campus_square/core/theme/theme_provider.dart';
import 'package:campus_square/core/services/notification_service.dart';
import 'package:campus_square/core/services/local_notification_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/shared/widgets/auth_route_guard.dart';
import 'package:campus_square/features/timetable/screens/alarm_screen.dart';

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
      child: CampusSquareApp(isAlarmLaunch: isAlarmLaunch),
    ),
  );
}

class CampusSquareApp extends StatelessWidget {
  const CampusSquareApp({super.key, required this.isAlarmLaunch});

  final bool isAlarmLaunch;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Campus Square',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: isAlarmLaunch ? const AlarmScreen() : const AuthRouteGuard(),
    );
  }
}
