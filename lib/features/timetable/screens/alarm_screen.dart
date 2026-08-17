import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class AlarmScreen extends StatefulWidget {
  final String? payload;
  const AlarmScreen({super.key, this.payload});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  static const platform = MethodChannel('campus_square/alarm_control');
  bool _isMarking = false;
  String? _eventId;
  String _eventTitle = "Class";

  @override
  void initState() {
    super.initState();
    _parsePayload();
    _enableLockScreen();
  }

  void _parsePayload() {
    if (widget.payload != null) {
      final parts = widget.payload!.split('|');
      if (parts.length > 1) _eventId = parts[1];
      if (parts.length > 2) _eventTitle = parts[2];
    }
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

  Future<void> _markAttendance(String status) async {
    if (_eventId == null) {
      _disableLockScreenAndClose();
      return;
    }
    setState(() => _isMarking = true);
    try {
      final auth = context.read<CampusSquareAuth>();
      final client = ApiClient(baseUrl: auth.baseUrl);
      final todayDateStr = DateTime.now().toIso8601String().split('T')[0];

      await client.authenticatedRequest(
        context,
        '/api/timetable/attendance',
        method: 'POST',
        body: jsonEncode({
          'event_id': _eventId,
          'date': todayDateStr,
          'status': status,
        }),
      );
    } catch (e) {
      debugPrint("Error marking attendance: $e");
    }
    _disableLockScreenAndClose();
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
                size: 80,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              Text(
                "$_eventTitle Starting Soon!",
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "Did you attend this class?",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 50),

              if (_isMarking)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      "Missed",
                      Colors.redAccent,
                      () => _markAttendance("MISSED"),
                    ),
                    const SizedBox(width: 20),
                    _buildActionButton(
                      "Attended",
                      Colors.green,
                      () => _markAttendance("ATTENDED"),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  "Cancelled",
                  Colors.orangeAccent,
                  () => _markAttendance("CANCELLED"),
                ),
                const SizedBox(height: 40),
                TextButton(
                  onPressed: _disableLockScreenAndClose,
                  child: const Text(
                    "Turn Off (Ignore)",
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
