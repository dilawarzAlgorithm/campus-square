import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/core/services/local_notification_service.dart';
import 'package:campus_square/features/timetable/screens/reminder_settings_widget.dart';
import 'package:campus_square/features/timetable/screens/subjects_dashboard_screen.dart';

class TimetableEvent {
  final String id;
  final String subjectId;
  final String title;
  final String location;
  final String type;
  final int dayOfWeek;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TimetableEvent({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.location,
    required this.type,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });
}

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<TimetableEvent> _events = [];
  List<dynamic> _subjects = [];
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
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final subRes = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/subjects",
        method: "GET",
      );
      if (!mounted) return;
      final evRes = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/events",
        method: "GET",
      );

      if (subRes.statusCode == 200 && evRes.statusCode == 200 && mounted) {
        _subjects = jsonDecode(subRes.body);
        final List<dynamic> rawEvents = jsonDecode(evRes.body);
        _events = rawEvents.map((e) {
          final sTime = e['start_time'].toString().split(':');
          final eTime = e['end_time'].toString().split(':');
          return TimetableEvent(
            id: e['id'],
            subjectId: e['subject_id'],
            title: e['title'],
            location: e['location'] ?? '',
            type: e['type'],
            dayOfWeek: e['day_of_week'],
            startTime: TimeOfDay(
              hour: int.parse(sTime[0]),
              minute: int.parse(sTime[1]),
            ),
            endTime: TimeOfDay(
              hour: int.parse(eTime[0]),
              minute: int.parse(eTime[1]),
            ),
          );
        }).toList();

        LocalNotificationService.scheduleClassReminders(_events);
      }
    } catch (e) {
      debugPrint("Timetable load error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addOrEditEvent({TimetableEvent? existingEvent}) {
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a Subject in the Dashboard first.'),
        ),
      );
      return;
    }

    final titleCtrl = TextEditingController(text: existingEvent?.title);
    final locCtrl = TextEditingController(text: existingEvent?.location);
    String type = existingEvent?.type ?? 'Class';
    String subjectId = existingEvent?.subjectId ?? _subjects.first['id'];
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
                  const Text(
                    'Schedule Event',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: subjectId,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      border: OutlineInputBorder(),
                    ),
                    items: _subjects
                        .map<DropdownMenuItem<String>>(
                          (s) => DropdownMenuItem(
                            value: s['id'],
                            child: Text(s['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setModalState(() => subjectId = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title / Info *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                          ),
                          items: ['Class', 'Lab', 'Exam']
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (v) => setModalState(() => type = v!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: day,
                          decoration: const InputDecoration(
                            labelText: 'Day',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(
                            7,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(_days[i]),
                            ),
                          ),
                          onChanged: (v) => setModalState(() => day = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
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
                    onPressed: () async {
                      if (titleCtrl.text.isEmpty) return;
                      final sTimeString =
                          "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00";
                      final eTimeString =
                          "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:00";

                      try {
                        final res = await _apiClient.authenticatedRequest(
                          context,
                          "/api/timetable/events",
                          method: "POST",
                          body: jsonEncode({
                            "subject_id": subjectId,
                            "title": titleCtrl.text,
                            "location": locCtrl.text,
                            "type": type,
                            "day_of_week": day,
                            "start_time": sTimeString,
                            "end_time": eTimeString,
                          }),
                        );
                        if (res.statusCode == 200 && context.mounted) {
                          Navigator.pop(ctx);
                          if (existingEvent != null) {
                            await _apiClient.authenticatedRequest(
                              context,
                              "/api/timetable/events/${existingEvent.id}",
                              method: "DELETE",
                            );
                          }
                          _fetchData();
                        }
                      } catch (e) {
                        // err
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
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

  void _deleteEvent(String id) async {
    try {
      await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/events/$id",
        method: "DELETE",
      );
      _fetchData();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timetable'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Subjects & Attendance',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubjectsDashboardScreen(),
                ),
              );
              _fetchData();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'timetable_fab',
        onPressed: _addOrEditEvent,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          ReminderSettingsWidget(myEvents: _events),
          const Divider(height: 1),
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
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
                          final sub = _subjects.firstWhere(
                            (s) => s['id'] == e.subjectId,
                            orElse: () => {'name': 'Unknown Subject'},
                          );

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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
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
                                            onPressed: () => _addOrEditEvent(
                                              existingEvent: e,
                                            ),
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
                                            onPressed: () => _deleteEvent(e.id),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    sub['name'],
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${e.type} • ${e.title} • ${e.location}",
                                    style: const TextStyle(
                                      color: Colors.blueGrey,
                                    ),
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
