import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:campus_square/features/timetable/screens/alarm_screen.dart';

class LocalNotificationService {
  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    tz.initializeTimeZones();

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_stat_notification');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == 'alarm_screen') {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AlarmScreen()),
            (route) => false,
          );
        }
      },
    );

    debugPrint("Local Notifications Initialized.");
  }

  static Future<void> _requestPermissionsSafely() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    await androidImplementation?.requestNotificationsPermission();

    await androidImplementation?.requestExactAlarmsPermission();
    await androidImplementation?.requestFullScreenIntentPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> scheduleClassReminders(
    List<dynamic> events, {
    int reminderMinutes = 10,
  }) async {
    await _requestPermissionsSafely();

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.cancelAll();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'class_reminders_v4',
          'Class Reminders',
          icon: 'ic_stat_notification',
          channelDescription: 'Offline reminders before class starts',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('class_alarm'),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          enableVibration: true,
          autoCancel: false,
          ongoing: true,
          visibility: NotificationVisibility.public,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'turn_off_id',
              'Turn Off Alarm',
              cancelNotification: true,
              showsUserInterface: true,
            ),
          ],
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    final now = DateTime.now();

    for (var event in events) {
      int daysUntil = (event.dayOfWeek - now.weekday) % 7;
      if (daysUntil < 0) daysUntil += 7;

      var scheduleTime =
          DateTime(
                now.year,
                now.month,
                now.day,
                event.startTime.hour,
                event.startTime.minute,
              )
              .add(Duration(days: daysUntil))
              .subtract(Duration(minutes: reminderMinutes));

      if (scheduleTime.isBefore(now)) {
        scheduleTime = scheduleTime.add(const Duration(days: 7));
      }

      final durationUntilAlarm = scheduleTime.difference(now);
      final tzScheduleTime = tz.TZDateTime.now(
        tz.local,
      ).add(durationUntilAlarm);

      final safeId = event.id.hashCode.abs() % 2147483647;

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: safeId,
          title: 'Upcoming ${event.type}: ${event.title}',
          body: 'Starts in $reminderMinutes mins at ${event.location}',
          scheduledDate: tzScheduleTime,
          notificationDetails: platformChannelSpecifics,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: 'alarm_screen',
        );
      } catch (e) {
        debugPrint("Failed to schedule alarm for ${event.title}: $e");
      }
    }

    debugPrint("Offline Reminders Scheduled Successfully!");
  }
}
