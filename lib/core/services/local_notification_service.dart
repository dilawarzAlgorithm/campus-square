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
        AndroidInitializationSettings('@mipmap/ic_launcher');
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

  static Future<void> scheduleClassReminders(List<dynamic> events) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin.cancelAll();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'class_reminders',
          'Class Reminders',
          channelDescription:
              'Offline reminders 10 minutes before class starts',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    final now = DateTime.now();

    for (var event in events) {
      int daysUntil = (event.dayOfWeek - now.weekday) % 7;
      if (daysUntil < 0) daysUntil += 7;

      var nextDate = now.add(Duration(days: daysUntil));

      var scheduleTime = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        event.startTime.hour,
        event.startTime.minute,
      ).subtract(const Duration(minutes: 10));

      if (scheduleTime.isBefore(now)) {
        scheduleTime = scheduleTime.add(const Duration(days: 7));
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: event.id.hashCode,
        title: 'Upcoming ${event.type}: ${event.title}',
        body: 'Starts in 10 mins at ${event.location}',
        scheduledDate: tz.TZDateTime.from(scheduleTime, tz.local),
        notificationDetails: platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    debugPrint("Offline Reminders Scheduled!");
  }
}
