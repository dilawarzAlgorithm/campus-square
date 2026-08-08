import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  static const platform = MethodChannel('campus_square/alarm_control');

  @override
  void initState() {
    super.initState();
    _enableLockScreen();
  }

  Future<void> _enableLockScreen() async {
    try {
      await platform.invokeMethod('enableLockScreen');
    } catch (e) {
      debugPrint("Failed to enable lock screen: $e");
    }
  }

  Future<void> _disableLockScreenAndClose() async {
    try {
      await platform.invokeMethod('disableLockScreen');
    } catch (e) {
      debugPrint("Failed to disable lock screen: $e");
    }

    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    await plugin.cancelAll();

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_active,
                size: 100,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 30),
              const Text(
                "Class Reminder!",
                style: TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _disableLockScreenAndClose,
                child: const Text(
                  "Turn Off",
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
