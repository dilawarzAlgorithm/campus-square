import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_square/core/services/local_notification_service.dart';

class TimetableEvent {
  final String id;
  final String title;
  final String location;
  final String type; // Class, Lab, Exam
  final int dayOfWeek; // 1 = Monday, 7 = Sunday
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  int attended;
  int total;

  TimetableEvent({
    required this.id,
    required this.title,
    required this.location,
    required this.type,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.attended = 0,
    this.total = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'location': location,
    'type': type,
    'dayOfWeek': dayOfWeek,
    'start_hour': startTime.hour,
    'start_minute': startTime.minute,
    'end_hour': endTime.hour,
    'end_minute': endTime.minute,
    'attended': attended,
    'total': total,
  };

  factory TimetableEvent.fromJson(Map<String, dynamic> json) => TimetableEvent(
    id: json['id'],
    title: json['title'],
    location: json['location'],
    type: json['type'],
    dayOfWeek: json['dayOfWeek'],
    startTime: TimeOfDay(
      hour: json['start_hour'],
      minute: json['start_minute'],
    ),
    endTime: TimeOfDay(hour: json['end_hour'], minute: json['end_minute']),
    attended: json['attended'] ?? 0,
    total: json['total'] ?? 0,
  );
}

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TimetableEvent> _events = [];

  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    int currentDay = DateTime.now().weekday - 1;
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: currentDay,
    );
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('local_timetable');
    if (data != null) {
      setState(() {
        _events = data
            .map((e) => TimetableEvent.fromJson(jsonDecode(e)))
            .toList();
      });
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _events.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('local_timetable', data);

    LocalNotificationService.scheduleClassReminders(_events);
  }

  void _addOrEditEvent({TimetableEvent? existingEvent}) {
    final titleCtrl = TextEditingController(text: existingEvent?.title);
    final locCtrl = TextEditingController(text: existingEvent?.location);
    String type = existingEvent?.type ?? 'Class';
    int day = existingEvent?.dayOfWeek ?? _tabController.index + 1;
    TimeOfDay start =
        existingEvent?.startTime ?? const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end =
        existingEvent?.endTime ?? const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existingEvent == null ? 'Add Schedule' : 'Edit Schedule',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Subject / Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location / Room',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Class', 'Lab', 'Exam']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setModalState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: day,
                    decoration: const InputDecoration(
                      labelText: 'Day of Week',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      7,
                      (i) =>
                          DropdownMenuItem(value: i + 1, child: Text(_days[i])),
                    ),
                    onChanged: (v) => setModalState(() => day = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: start,
                            );
                            if (t != null) setModalState(() => start = t);
                          },
                          child: Text("Start: ${start.format(context)}"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: end,
                            );
                            if (t != null) setModalState(() => end = t);
                          },
                          child: Text("End: ${end.format(context)}"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
                      if (titleCtrl.text.isEmpty) return;
                      setState(() {
                        if (existingEvent != null) {
                          _events.remove(existingEvent);
                        }
                        _events.add(
                          TimetableEvent(
                            id:
                                existingEvent?.id ??
                                DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                            title: titleCtrl.text,
                            location: locCtrl.text,
                            type: type,
                            dayOfWeek: day,
                            startTime: start,
                            endTime: end,
                            attended: existingEvent?.attended ?? 0,
                            total: existingEvent?.total ?? 0,
                          ),
                        );
                      });
                      _saveEvents();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save Event'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _markAttendance(TimetableEvent event, bool attended) {
    setState(() {
      event.total += 1;
      if (attended) event.attended += 1;
    });
    _saveEvents();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addOrEditEvent,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            color: theme.cardColor,
            child: TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: Colors.grey,
              isScrollable: true,
              indicatorColor: theme.colorScheme.primary,
              tabs: _days.map((day) => Tab(text: day)).toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(7, (index) {
                final dayEvents = _events
                    .where((e) => e.dayOfWeek == index + 1)
                    .toList();
                dayEvents.sort(
                  (a, b) => a.startTime.hour.compareTo(b.startTime.hour),
                );

                if (dayEvents.isEmpty) {
                  return const Center(
                    child: Text(
                      "No classes scheduled.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: dayEvents.length,
                  itemBuilder: (context, i) {
                    final e = dayEvents[i];
                    final double attPercentage = e.total == 0
                        ? 100.0
                        : (e.attended / e.total) * 100;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${e.startTime.format(context)} - ${e.endTime.format(context)}",
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _addOrEditEvent(existingEvent: e),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      onPressed: () {
                                        setState(() => _events.remove(e));
                                        _saveEvents();
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              e.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${e.type} • ${e.location}",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Attendance",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      "${attPercentage.toStringAsFixed(1)}% (${e.attended}/${e.total})",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: attPercentage < 75
                                            ? Colors.red
                                            : Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade50,
                                        foregroundColor: Colors.red,
                                        elevation: 0,
                                      ),
                                      onPressed: () =>
                                          _markAttendance(e, false),
                                      child: const Text('Miss'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade50,
                                        foregroundColor: Colors.green,
                                        elevation: 0,
                                      ),
                                      onPressed: () => _markAttendance(e, true),
                                      child: const Text('Attend'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
