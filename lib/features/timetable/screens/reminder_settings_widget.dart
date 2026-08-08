import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_square/core/services/local_notification_service.dart';

class ReminderSettingsWidget extends StatefulWidget {
  final List<dynamic> myEvents;

  const ReminderSettingsWidget({super.key, required this.myEvents});

  @override
  State<ReminderSettingsWidget> createState() => _ReminderSettingsWidgetState();
}

class _ReminderSettingsWidgetState extends State<ReminderSettingsWidget> {
  int _selectedMinutes = 10;

  @override
  void initState() {
    super.initState();
    _loadSavedPreference();
  }

  Future<void> _loadSavedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedMinutes = prefs.getInt('reminder_minutes') ?? 10;
    });
  }

  Future<void> _updateReminderTime(int? newMinutes) async {
    if (newMinutes == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_minutes', newMinutes);

    setState(() {
      _selectedMinutes = newMinutes;
    });

    await LocalNotificationService.scheduleClassReminders(
      widget.myEvents,
      reminderMinutes: _selectedMinutes,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminders set for $_selectedMinutes minutes before class!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Remind me before class:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedMinutes,
                items: const [
                  DropdownMenuItem(value: 5, child: Text("5 Minutes")),
                  DropdownMenuItem(value: 10, child: Text("10 Minutes")),
                  DropdownMenuItem(value: 15, child: Text("15 Minutes")),
                  DropdownMenuItem(value: 30, child: Text("30 Minutes")),
                ],
                onChanged: _updateReminderTime,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
