import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static Future<void> initialize() async {
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
    );

    debugPrint("Local Notifications Initialized.");
  }

  static Future<void> _requestPermissionsSafely() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> scheduleClassReminders(List<dynamic> events) async {
    await _requestPermissionsSafely();

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin.cancelAll();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'class_reminders',
          'Class Reminders',
          icon: 'ic_stat_notification',
          channelDescription:
              'Offline reminders 10 minutes before class starts',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    final now = DateTime.now();

    for (var event in events) {
      int daysUntil = (event.dayOfWeek - now.weekday) % 7;
      if (daysUntil < 0) daysUntil += 7;

      var scheduleTime = DateTime(
        now.year,
        now.month,
        now.day,
        event.startTime.hour,
        event.startTime.minute,
      ).add(Duration(days: daysUntil)).subtract(const Duration(minutes: 10));

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
          title: 'Upcoming ${event.type}:${event.title}',
          body: 'Starts in 10 mins at ${event.location}',
          scheduledDate: tzScheduleTime,
          notificationDetails: platformChannelSpecifics,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (e) {
        debugPrint("Failed to schedule alarm for ${event.title}:$e");
      }
    }

    debugPrint("Offline Reminders Scheduled Successfully!");
  }
}
